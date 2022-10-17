import {
  Loader,
  baseRealm,
  baseCardRef,
  LooseCardResource,
  isCardResource,
  internalKeyFor,
  trimExecutableExtension,
  hasExecutableExtension,
  type Card,
  type CardAPI,
} from ".";
import { Kind, Realm, getExportedCardContext } from "./realm";
import { RealmPaths, LocalPath } from "./paths";
import ignore, { Ignore } from "ignore";
import isEqual from "lodash/isEqual";
import { Deferred } from "./deferred";
import flatMap from "lodash/flatMap";
import merge from "lodash/merge";
import type {
  ExportedCardRef,
  CardRef,
  CardResource,
  SingleCardDocument,
} from "./search-index";

// Forces callers to use URL (which avoids accidentally using relative url
// strings without a base)
class URLMap<T> {
  #map: Map<string, T>;
  constructor();
  constructor(mapTuple: [key: URL, value: T][]);
  constructor(map: URLMap<T>);
  constructor(mapInit: URLMap<T> | [key: URL, value: T][] = []) {
    if (!Array.isArray(mapInit)) {
      mapInit = [...mapInit];
    }
    this.#map = new Map(mapInit.map(([key, value]) => [key.href, value]));
  }
  has(url: URL): boolean {
    return this.#map.has(url.href);
  }
  get(url: URL): T | undefined {
    return this.#map.get(url.href);
  }
  set(url: URL, value: T) {
    return this.#map.set(url.href, value);
  }
  get [Symbol.iterator]() {
    let self = this;
    return function* () {
      for (let [key, value] of self.#map) {
        yield [new URL(key), value] as [URL, T];
      }
    };
  }
  values() {
    return this.#map.values();
  }
  keys() {
    let self = this;
    return {
      get [Symbol.iterator]() {
        return function* () {
          for (let key of self.#map.keys()) {
            yield new URL(key);
          }
        };
      },
    };
  }
  get size() {
    return this.#map.size;
  }
  remove(url: URL) {
    return this.#map.delete(url.href);
  }
}

interface IndexError {
  message: string;
  errorReferences?: string[];
  // TODO we need to serialize the stack trace too, checkout the mono repo card compiler for examples
  // TODO when we support relationships we'll need to have instance references too.
}
export interface SearchEntry {
  resource: CardResource;
  searchData: Record<string, any>;
  types: string[];
  deps: Set<string>;
}

interface Reader {
  readFileAsText: (
    path: LocalPath,
    opts?: { withFallbacks?: true }
  ) => Promise<{ content: string; lastModified: number } | undefined>;
  readdir: (
    path: string
  ) => AsyncGenerator<{ name: string; path: string; kind: Kind }, void>;
}

interface Stats {
  instancesIndexed: number;
  instanceErrors: number;
  moduleErrors: number;
}

export type SearchEntryWithErrors =
  | { type: "entry"; entry: SearchEntry }
  | { type: "error"; error: IndexError };
type TypesWithErrors =
  | { type: "types"; types: string[] }
  | { type: "error"; error: IndexError };

interface Module {
  url: string;
  consumes: string[];
}
type ModuleWithErrors =
  | { type: "module"; module: Module }
  | { type: "error"; moduleURL: string; error: IndexError };

export class CurrentRun {
  #instances: URLMap<SearchEntryWithErrors>;
  #modules = new Map<string, ModuleWithErrors>();
  #moduleWorkingCache = new Map<string, Promise<Module>>();
  #typesCache = new WeakMap<typeof Card, Promise<TypesWithErrors>>();
  #reader: Reader | undefined;
  #realmPaths: RealmPaths;
  #ignoreMap: URLMap<Ignore>;
  #loader = Loader.createLoaderFromGlobal();
  private realm: Realm;
  readonly stats: Stats = {
    instancesIndexed: 0,
    instanceErrors: 0,
    moduleErrors: 0,
  };

  private constructor({
    realm,
    reader,
    instances,
    modules,
    ignoreMap,
  }: {
    realm: Realm;
    reader: Reader | undefined; // the "empty" case doesn't need a reader
    instances: URLMap<SearchEntryWithErrors>;
    modules: Map<string, ModuleWithErrors>;
    ignoreMap: URLMap<Ignore>;
  }) {
    this.#realmPaths = new RealmPaths(realm.url);
    this.#reader = reader;
    this.realm = realm;
    this.#instances = instances;
    this.#modules = modules;
    this.#ignoreMap = ignoreMap;
  }

  static empty(realm: Realm) {
    return new this({
      realm,
      reader: undefined,
      instances: new URLMap(),
      modules: new Map(),
      ignoreMap: new URLMap(),
    });
  }

  static async fromScratch(realm: Realm, reader: Reader) {
    let current = new this({
      realm,
      reader,
      instances: new URLMap(),
      modules: new Map(),
      ignoreMap: new URLMap(),
    });
    await current.visitDirectory(new URL(realm.url));
    return current;
  }

  static async incremental(
    url: URL,
    operation: "update" | "delete",
    prev: CurrentRun
  ) {
    let instances = new URLMap(prev.instances);
    let ignoreMap = new URLMap(prev.ignoreMap);
    let modules = new Map(prev.modules);
    instances.remove(new URL(url.href.replace(/\.json$/, "")));

    let invalidations = flatMap(invalidate(url, modules, instances), (u) =>
      // we only ever want to visit our own URL in the update case so we'll do
      // that explicitly
      u !== url.href && u !== trimExecutableExtension(url).href
        ? [new URL(u)]
        : []
    );

    let current = new this({
      realm: prev.realm,
      reader: prev.reader,
      instances,
      modules,
      ignoreMap,
    });

    if (operation === "update") {
      await current.visitFile(url);
    }

    for (let invalidation of invalidations) {
      await current.visitFile(invalidation);
    }

    return current;
  }

  private get reader(): Reader {
    if (!this.#reader) {
      throw new Error(`The reader is not available`);
    }
    return this.#reader;
  }

  public get instances() {
    return this.#instances;
  }

  public get modules() {
    return this.#modules;
  }

  public get ignoreMap() {
    return this.#ignoreMap;
  }

  public get loader() {
    return this.#loader;
  }

  private async visitDirectory(url: URL): Promise<void> {
    let ignorePatterns = await this.reader.readFileAsText(
      this.#realmPaths.local(new URL(".gitignore", url))
    );
    if (ignorePatterns && ignorePatterns.content) {
      this.#ignoreMap.set(url, ignore().add(ignorePatterns.content));
    }

    for await (let { path: innerPath, kind } of this.reader.readdir(
      this.#realmPaths.local(url)
    )) {
      let innerURL = this.#realmPaths.fileURL(innerPath);
      if (this.isIgnored(innerURL)) {
        continue;
      }
      if (kind === "file") {
        await this.visitFile(innerURL);
      } else {
        let directoryURL = this.#realmPaths.directoryURL(innerPath);
        await this.visitDirectory(directoryURL);
      }
    }
  }

  private async visitFile(url: URL): Promise<void> {
    if (this.isIgnored(url)) {
      return;
    }

    if (
      (hasExecutableExtension(url.href) ||
        // handle modules with no extension too
        !url.href.split("/").pop()!.includes(".")) &&
      url.href !== `${baseRealm.url}card-api.gts` // TODO the base card's module is not analyzable
    ) {
      return await this.indexCardSource(url);
    }

    let localPath = this.#realmPaths.local(url);
    let fileRef = await this.reader.readFileAsText(localPath);
    if (!fileRef) {
      throw new Error(`missing file ${localPath}`);
    }

    let { content, lastModified } = fileRef;
    if (url.href.endsWith(".json")) {
      let { data: resource } = JSON.parse(content);
      if (isCardResource(resource)) {
        await this.indexCard(localPath, lastModified, resource);
      }
    }
  }

  private async indexCardSource(url: URL): Promise<void> {
    let module: Record<string, unknown>;
    try {
      module = await this.loader.import(url.href);
    } catch (err: any) {
      this.stats.moduleErrors++;
      if (globalThis.process?.env?.SUPPRESS_ERRORS !== "true") {
        console.warn(
          `encountered error loading module "${url.href}": ${err.message}`
        );
      }
      let errorReferences = await (
        await this.loader.getConsumedModules(url.href)
      ).filter((u) => u !== url.href);
      this.#modules.set(url.href, {
        type: "error",
        moduleURL: url.href,
        error: {
          message: `encountered error loading module "${url.href}": ${err.message}`,
          errorReferences,
        },
      });
      return;
    }

    let refs = Object.values(module)
      .filter(
        (maybeCard) =>
          typeof maybeCard === "function" && "baseCard" in maybeCard
      )
      .map((card) => Loader.identify(card))
      .filter(Boolean) as ExportedCardRef[];
    for (let ref of refs) {
      await this.buildModule(ref.module, url);
    }
  }

  private async indexCard(
    path: LocalPath,
    lastModified: number,
    resource: LooseCardResource
  ): Promise<void> {
    let instanceURL = new URL(
      this.#realmPaths.fileURL(path).href.replace(/\.json$/, "")
    );
    let moduleURL = new URL(
      resource.meta.adoptsFrom.module,
      new URL(path, this.realm.url)
    );
    let name = resource.meta.adoptsFrom.name;
    let cardRef = { module: moduleURL.href, name };
    let typesMaybeError: TypesWithErrors | undefined;
    let uncaughtError: Error | undefined;
    let doc: SingleCardDocument | undefined;
    let searchData: any;
    let cardType: typeof Card | undefined;
    try {
      let api = await this.#loader.import<CardAPI>(`${baseRealm.url}card-api`);
      let card = await api.createFromSerialized(resource, moduleURL, {
        loader: this.#loader,
      });
      cardType = Reflect.getPrototypeOf(card)?.constructor as typeof Card;
      await api.recompute(card);
      let data: SingleCardDocument = api.serializeCard(card, {
        includeComputeds: true,
      });
      let maybeDoc = merge(data, {
        data: {
          id: instanceURL.href,
          meta: { lastModified: lastModified },
        },
      });
      doc = maybeDoc;
      searchData = await api.searchDoc(card);
    } catch (err: any) {
      uncaughtError = err;
    }
    // if we already encountered an uncaught error then no need to deal with this
    if (!uncaughtError && cardType) {
      typesMaybeError = await this.getTypes(cardType);
    }
    if (doc && typesMaybeError?.type === "types") {
      this.stats.instancesIndexed++;
      this.#instances.set(instanceURL, {
        type: "entry",
        entry: {
          resource: doc.data,
          searchData,
          types: typesMaybeError.types,
          deps: new Set([
            ...(await this.loader.getConsumedModules(moduleURL.href)).filter(
              (u) => u !== moduleURL.href
            ),
            moduleURL.href,
          ]),
        },
      });
    }

    if (uncaughtError || typesMaybeError?.type === "error") {
      this.stats.instanceErrors++;
      let error: SearchEntryWithErrors;
      if (uncaughtError) {
        error = {
          type: "error",
          error: {
            message: `${uncaughtError.message} (TODO include stack trace)`,
            errorReferences: [cardRef.module],
          },
        };
      } else if (typesMaybeError?.type === "error") {
        error = { type: "error", error: typesMaybeError.error };
      } else {
        throw new Error(`bug: should never get here`);
      }
      if (globalThis.process?.env?.SUPPRESS_ERRORS !== "true") {
        console.warn(
          `encountered error indexing card instance ${path}: ${error.error.message}`
        );
      }
      this.#instances.set(instanceURL, error);
    }
  }

  public async buildModule(
    moduleIdentifier: string,
    relativeTo = new URL(this.realm.url)
  ): Promise<void> {
    let url = new URL(moduleIdentifier, relativeTo).href;
    let existing = this.#modules.get(url);
    if (existing?.type === "error") {
      throw new Error(
        `bug: card definition has errors which should never happen since the card already executed successfully: ${url}`
      );
    }
    if (existing) {
      return;
    }

    let working = this.#moduleWorkingCache.get(url);
    if (working) {
      await working;
      return;
    }

    let deferred = new Deferred<Module>();
    this.#moduleWorkingCache.set(url, deferred.promise);
    let m = await this.#loader.import<Record<string, any>>(moduleIdentifier);
    if (m) {
      for (let exportName of Object.keys(m)) {
        m[exportName];
      }
    }
    let consumes = await (
      await this.loader.getConsumedModules(url)
    ).filter((u) => u !== url);
    let module: Module = {
      url,
      consumes,
    };
    this.#modules.set(url, { type: "module", module });
    deferred.fulfill(module);
  }

  private async getTypes(card: typeof Card): Promise<TypesWithErrors> {
    let cached = this.#typesCache.get(card);
    if (cached) {
      return await cached;
    }
    let ref = this.#loader.identify(card);
    if (!ref) {
      throw new Error(`could not identify card ${card.name}`);
    }
    let deferred = new Deferred<TypesWithErrors>();
    this.#typesCache.set(card, deferred.promise);
    let types: string[] = [];
    let fullRef: CardRef = { type: "exportedCard", ...ref };
    while (fullRef) {
      let loadedCard = (await this.loadCard(fullRef)) as
        | {
            card: typeof Card;
            ref: CardRef;
          }
        | undefined;
      if (!loadedCard) {
        let { module } = getExportedCardContext(fullRef);
        let result: TypesWithErrors = {
          type: "error",
          error: {
            message: `Unable to determine card types for ${JSON.stringify(
              ref
            )}`,
            errorReferences: [module],
          },
        };
        deferred.fulfill(result);
        return result;
      }
      types.push(internalKeyFor(loadedCard.ref, undefined));
      if (!isEqual(loadedCard.ref, { type: "exportedCard", ...baseCardRef })) {
        fullRef = { type: "ancestorOf", card: loadedCard.ref };
      } else {
        break;
      }
    }
    let result: TypesWithErrors = { type: "types", types };
    deferred.fulfill(result);
    return result;
  }

  public isIgnored(url: URL): boolean {
    if (url.href === this.realm.url) {
      return false; // you can't ignore the entire realm
    }
    if (this.ignoreMap.size === 0) {
      return false;
    }
    // Test URL against closest ignore. (Should the ignores cascade? so that the
    // child ignore extends the parent ignore?)
    let ignoreURLs = [...this.ignoreMap.keys()].map((u) => u.href);
    let matchingIgnores = ignoreURLs.filter((u) => url.href.includes(u));
    let ignoreURL = matchingIgnores.sort((a, b) => b.length - a.length)[0] as
      | string
      | undefined;
    if (!ignoreURL) {
      return false;
    }
    let ignore = this.ignoreMap.get(new URL(ignoreURL))!;
    let pathname = this.#realmPaths.local(url);
    return ignore.test(pathname).ignored;
  }

  private async loadCard(
    ref: CardRef
  ): Promise<{ card: typeof Card; ref: CardRef } | undefined> {
    let maybeCard: unknown;
    let canonicalRef: CardRef | undefined;
    if (ref.type === "exportedCard") {
      let module = await this.loader.import<Record<string, any>>(ref.module);
      maybeCard = module[ref.name];
      canonicalRef = { ...ref, ...Loader.identify(maybeCard) };
    } else if (ref.type === "ancestorOf") {
      let { card: child, ref: childRef } =
        (await this.loadCard(ref.card)) ?? {};
      if (!child || !childRef) {
        return undefined;
      }
      maybeCard = Reflect.getPrototypeOf(child) as typeof Card;
      let cardId = Loader.identify(maybeCard);
      canonicalRef = cardId
        ? { type: "exportedCard", ...cardId }
        : { ...ref, card: childRef };
    } else if (ref.type === "fieldOf") {
      let { card: parent, ref: parentRef } =
        (await this.loadCard(ref.card)) ?? {};
      if (!parent || !parentRef) {
        return undefined;
      }
      let api = await this.loader.import<CardAPI>(`${baseRealm.url}card-api`);
      let field = api.getField(parent, ref.field);
      maybeCard = field?.card;
      let cardId = Loader.identify(maybeCard);
      canonicalRef = cardId
        ? { type: "exportedCard", ...cardId }
        : { ...ref, card: parentRef };
    } else {
      throw assertNever(ref);
    }

    if (
      typeof maybeCard === "function" &&
      "baseCard" in maybeCard &&
      canonicalRef
    ) {
      return {
        card: maybeCard as unknown as typeof Card,
        ref: canonicalRef,
      };
    } else {
      return undefined;
    }
  }
}

function invalidate(
  url: URL,
  modules: Map<string, ModuleWithErrors>,
  instances: URLMap<SearchEntryWithErrors>,
  invalidations: string[] = [],
  visited: Set<string> = new Set()
): string[] {
  if (visited.has(url.href)) {
    return [];
  }

  let invalidationSet = new Set(invalidations);
  // invalidate any instances whose deps come from the URL or whose error depends on the URL
  let invalidatedInstances = [...instances]
    .filter(([instanceURL, item]) => {
      if (item.type === "error") {
        for (let errorModule of item.error.errorReferences ?? []) {
          if (
            errorModule === url.href ||
            errorModule === trimExecutableExtension(url).href
          ) {
            instances.remove(instanceURL); // note this is a side-effect
            return true;
          }
        }
      } else {
        if (
          item.entry.deps.has(url.href) ||
          item.entry.deps.has(trimExecutableExtension(url).href)
        ) {
          instances.remove(instanceURL); // note this is a side-effect
          return true;
        }
      }
      return false;
    })
    .map(([u]) => `${u.href}.json`);
  for (let invalidation of invalidatedInstances) {
    invalidationSet.add(invalidation);
  }

  for (let [key, maybeError] of [...modules]) {
    if (maybeError.type === "error") {
      // invalidate any errored modules that come from the URL
      let errorModule = maybeError.moduleURL;
      if (
        errorModule === url.href ||
        errorModule === trimExecutableExtension(url).href
      ) {
        modules.delete(key);
        invalidationSet.add(errorModule);
      }

      // invalidate any modules in an error state whose errorReference comes
      // from the URL
      for (let maybeDef of maybeError.error.errorReferences ?? []) {
        if (
          maybeDef === url.href ||
          maybeDef === trimExecutableExtension(url).href
        ) {
          for (let invalidation of invalidate(
            new URL(errorModule),
            modules,
            instances,
            [...invalidationSet],
            new Set([...visited, url.href])
          )) {
            invalidationSet.add(invalidation);
          }
          // no need to test the other error refs, we have already decided to
          // invalidate this URL
          break;
        }
      }
      continue;
    }

    let { module } = maybeError;
    // invalidate any modules that come from the URL
    if (
      module.url === url.href ||
      module.url === trimExecutableExtension(url).href
    ) {
      modules.delete(key);
      invalidationSet.add(module.url);
    }

    // invalidate any modules that consume the URL
    for (let importURL of module.consumes) {
      if (
        importURL === url.href ||
        importURL === trimExecutableExtension(url).href
      ) {
        for (let invalidation of invalidate(
          new URL(module.url),
          modules,
          instances,
          [...invalidationSet],
          new Set([...visited, url.href])
        )) {
          invalidationSet.add(invalidation);
        }
        // no need to test the other imports, we have already decided to
        // invalidate this URL
        break;
      }
    }
  }

  return [...invalidationSet];
}

function assertNever(value: never) {
  return new Error(`should never happen ${value}`);
}
