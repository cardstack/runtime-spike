import { executableExtensions, baseRealm } from ".";
import {
  Kind,
  Realm,
  CardDefinitionResource,
  getExportedCardContext,
} from "./realm";
import { RealmPaths, LocalPath } from "./paths";
import { ModuleSyntax } from "./module-syntax";
import { ClassReference, PossibleCardClass } from "./schema-analysis-plugin";
import ignore, { Ignore } from "ignore";
import { stringify } from "qs";
import { Query, Filter, Sort } from "./query";
import { Loader } from "./loader";
import { Deferred } from "./deferred";
//@ts-ignore realm server TSC doesn't know how to deal with this because it doesn't understand glint
import type { Card } from "https://cardstack.com/base/card-api";
//@ts-ignore realm server TSC doesn't know how to deal with this because it doesn't understand glint
type CardAPI = typeof import("https://cardstack.com/base/card-api");

export type ExportedCardRef = {
  module: string;
  name: string;
};

export type CardRef =
  | {
      type: "exportedCard";
      module: string;
      name: string;
    }
  | {
      type: "ancestorOf";
      card: CardRef;
    }
  | {
      type: "fieldOf";
      card: CardRef;
      field: string;
    };

export function isCardRef(ref: any): ref is CardRef {
  if (typeof ref !== "object") {
    return false;
  }
  if (!("type" in ref)) {
    return false;
  }
  if (ref.type === "exportedCard") {
    if (!("module" in ref) || !("name" in ref)) {
      return false;
    }
    return typeof ref.module === "string" && typeof ref.name === "string";
  } else if (ref.type === "ancestorOf") {
    if (!("card" in ref)) {
      return false;
    }
    return isCardRef(ref.card);
  } else if (ref.type === "fieldOf") {
    if (!("card" in ref) || !("field" in ref)) {
      return false;
    }
    if (typeof ref.card !== "object" || typeof ref.field !== "string") {
      return false;
    }
    return isCardRef(ref.card);
  }
  return false;
}

// TODO
export type Saved = string;
export type Unsaved = string | undefined;
export interface CardResource<Identity extends Unsaved = Saved> {
  id: Identity;
  type: "card";
  attributes?: Record<string, any>;
  // TODO add relationships
  meta: {
    adoptsFrom: {
      module: string;
      name: string;
    };
    lastModified?: number;
  };
  links?: {
    self?: string;
  };
}
export interface CardDocument<Identity extends Unsaved = Saved> {
  data: CardResource<Identity>;
}

export function isCardResource(resource: any): resource is CardResource {
  if (typeof resource !== "object") {
    return false;
  }
  if ("id" in resource && typeof resource.id !== "string") {
    return false;
  }
  if (!("type" in resource) || resource.type !== "card") {
    return false;
  }
  if ("attributes" in resource && typeof resource.attributes !== "object") {
    return false;
  }
  if (!("meta" in resource) || typeof resource.meta !== "object") {
    return false;
  }
  let { meta } = resource;
  if (!("adoptsFrom" in meta) && typeof meta.adoptsFrom !== "object") {
    return false;
  }
  let { adoptsFrom } = meta;
  return (
    "module" in adoptsFrom &&
    typeof adoptsFrom.module === "string" &&
    "name" in adoptsFrom &&
    typeof adoptsFrom.name === "string"
  );
}
export function isCardDocument(doc: any): doc is CardDocument {
  if (typeof doc !== "object") {
    return false;
  }
  return "data" in doc && isCardResource(doc.data);
}

export interface CardDefinition {
  id: CardRef;
  key: string; // this is used to help for JSON-API serialization
  super: CardRef | undefined; // base card has no super
  fields: Map<
    string,
    {
      fieldType: "contains" | "containsMany";
      fieldCard: CardRef;
    }
  >;
}

function hasExecutableExtension(path: string): boolean {
  for (let extension of executableExtensions) {
    if (path.endsWith(extension)) {
      return true;
    }
  }
  return false;
}

function trimExecutableExtension(url: URL): URL {
  for (let extension of executableExtensions) {
    if (url.href.endsWith(extension)) {
      return new URL(url.href.replace(new RegExp(`\\${extension}$`), ""));
    }
  }
  return url;
}

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

interface SearchEntry {
  resource: CardResource;
  searchData: Record<string, any>;
  types: string[] | undefined; // theses start out undefined during indexing and get defined during semantic phase
}

interface Reader {
  readFileAsText: (
    path: LocalPath
  ) => Promise<{ content: string; lastModified: number } | undefined>;
  readdir: (
    path: string
  ) => AsyncGenerator<{ name: string; path: string; kind: Kind }, void>;
}

class CurrentRun {
  static empty(realm: Realm) {
    return new this({
      realm,
      reader: undefined,
      instances: new URLMap(),
      modules: new URLMap(),
      definitions: new Map(),
      incremental: undefined,
    });
  }

  static async fromScratch(realm: Realm, reader: Reader) {
    let current = new this({
      realm,
      reader,
      instances: new URLMap(),
      modules: new URLMap(),
      // TODO need to investigate the syntax analysis of the base card--if that
      // is not possible to do, then we should seed it here
      definitions: new Map(),
      incremental: undefined,
    });
    await current.run();
    return current;
  }

  static async incremental(
    url: URL,
    operation: "update" | "delete",
    prev: CurrentRun
  ) {
    let nextInstances = new URLMap(prev.instances);
    nextInstances.remove(url);
    let nextModules = new URLMap(prev.modules);
    maybeRemoveModules(url, nextModules);
    let nextDefinitions = new Map(prev.definitions);
    removeCardsInURL(url, nextDefinitions);
    let current = new this({
      realm: prev.realm,
      reader: prev.reader,
      instances: nextInstances,
      modules: nextModules,
      definitions: nextDefinitions,
      incremental: {
        url,
        operation,
      },
    });
    await current.run();
    return current;
  }

  #touched = new Set<unknown>();
  #realmPaths: RealmPaths;
  #api: CardAPI | undefined;
  #reader: Reader | undefined;
  // TODO refactor this into just using our this.definitions
  #externalDefinitionsCache = new Map<
    string,
    Promise<CardDefinition | undefined>
  >();

  readonly realm: Realm;
  // idea is that we always trust these caches, anything that's not up to date is not in here
  readonly instances: URLMap<SearchEntry>;
  readonly modules: URLMap<ModuleSyntax>;
  readonly definitions: Map<string, CardDefinition>;
  private incremental: { url: URL; operation: "update" | "delete" } | undefined;
  private ignoreMap = new URLMap<Ignore>();

  private async run() {
    this.#api = await Loader.import<CardAPI>(`${baseRealm.url}card-api`);
    if (this.incremental) {
      if (this.incremental.operation === "delete") {
        this.#touched.add(this.incremental.url);
      } else {
        await this.visitFile(this.incremental.url);
      }
    } else {
      await this.visitDirectory(new URL(this.realm.url));
    }
    await this.handleInvalidations();
  }

  private get api(): CardAPI {
    if (!this.#api) {
      throw new Error(`Card API was accessed before it was loaded`);
    }
    return this.#api;
  }

  private get reader(): Reader {
    if (!this.#reader) {
      throw new Error(`The reader is not available`);
    }
    return this.#reader;
  }

  private constructor({
    realm,
    reader,
    instances,
    modules,
    definitions,
    incremental,
  }: {
    realm: Realm;
    reader: Reader | undefined; // the "empty" case doesn't need a reader
    instances: URLMap<SearchEntry>;
    modules: URLMap<ModuleSyntax>;
    definitions: Map<string, CardDefinition>;
    incremental: { url: URL; operation: "update" | "delete" } | undefined;
  }) {
    this.#realmPaths = new RealmPaths(realm.url);
    this.#reader = reader;
    this.realm = realm;
    this.instances = instances;
    this.modules = modules;
    this.definitions = definitions;
    this.incremental = incremental;
  }

  private async visitDirectory(url: URL): Promise<void> {
    let ignorePatterns = await this.reader.readFileAsText(
      this.#realmPaths.local(new URL(".gitignore", url))
    );
    if (ignorePatterns && ignorePatterns.content) {
      this.ignoreMap.set(url, ignore().add(ignorePatterns.content));
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

  // this should recurse all the way into buildDefinition (which should become
  // more like "typeOf") as needed
  //
  // typeOf should recurse into visitFile as needed when we don't already have a
  // thing in this.modules.
  //
  // the trustworthy caches are what prevent this from duplicating work
  private async visitFile(url: URL): Promise<void> {
    if (this.isIgnored(url)) {
      return;
    }

    let localPath = this.#realmPaths.local(url);
    let fileRef = await this.reader.readFileAsText(localPath);
    if (!fileRef) {
      return;
    }
    let { content, lastModified } = fileRef;
    if (url.href.endsWith(".json")) {
      let json = JSON.parse(content);
      if (isCardDocument(json)) {
        let instanceURL = new URL(url.href.replace(/\.json$/, ""));
        json.data.id = instanceURL.href;
        json.data.meta.lastModified = lastModified;
        let module = await Loader.import<Record<string, any>>(
          new URL(
            json.data.meta.adoptsFrom.module,
            new URL(localPath, this.realm.url)
          ).href
        );
        let CardClass = module[json.data.meta.adoptsFrom.name] as typeof Card;
        let card = CardClass.fromSerialized(json.data.attributes);
        this.instances.set(instanceURL, {
          resource: json.data,
          searchData: await this.api.searchDoc(card),
          types: undefined,
        });
      }
    } else if (
      hasExecutableExtension(url.href) &&
      url.href !== `${baseRealm.url}card-api.gts` // the base card's module is not analyzable
    ) {
      let mod = new ModuleSyntax(content);
      this.modules.set(url, mod);
      this.modules.set(trimExecutableExtension(url), mod);

      // refactor note: this was previously from the guts of semanticPhase that
      // starts us down the path of making definitions for the analyzed modules.
      // i think we need to recurse back into this method from
      // this.lookupPossibleCard(), which will crawl thru the super classes and
      // fields expecting to discover more module syntax, which may not be built
      // yet. we'll probably need to cache to the promises for the creation of
      // these syntax files to prevent us from redoing work in the case where
      // multiple cards consume the same module. that probably means a deferred
      // that is created in the beginning of this method, and fulfilled above
      // when the module syntax is this in this.modules (where we actually save
      // promises in this.modules)
      for (let possibleCard of mod.possibleCards) {
        if (possibleCard.exportedAs) {
          if (this.isIgnored(url)) {
            continue;
          }
          await this.buildDefinition(
            url,
            mod,
            {
              type: "exportedCard",
              module: url.href,
              name: possibleCard.exportedAs,
            },
            possibleCard
          );
        }
      }
    }
  }

  private async buildDefinition(
    url: URL,
    mod: ModuleSyntax,
    ref: CardRef,
    possibleCard: PossibleCardClass
  ): Promise<CardDefinition | undefined> {
    let id: CardRef = possibleCard.exportedAs
      ? {
          type: "exportedCard",
          module: trimExecutableExtension(new URL(url, this.realm.url)).href,
          name: possibleCard.exportedAs,
        }
      : ref;

    let def = this.definitions.get(internalKeyFor(id, url));
    if (def) {
      this.definitions.set(internalKeyFor(ref, url), def);
      return def;
    }

    let superDef = await this.definitionForClassRef(
      url,
      mod,
      possibleCard.super,
      { type: "ancestorOf", card: id }
    );

    if (!superDef) {
      return undefined;
    }

    let fields: CardDefinition["fields"] = new Map(superDef.fields);

    for (let [fieldName, possibleField] of possibleCard.possibleFields) {
      if (!isOurFieldDecorator(possibleField.decorator, url)) {
        continue;
      }
      let fieldType = getFieldType(possibleField.type, url);
      if (!fieldType) {
        continue;
      }
      let fieldDef = await this.definitionForClassRef(
        url,
        mod,
        possibleField.card,
        { type: "fieldOf", card: id, field: fieldName }
      );
      if (fieldDef) {
        fields.set(fieldName, { fieldType, fieldCard: fieldDef.id });
      }
    }

    let key = internalKeyFor(id, url);
    def = { id, key, super: superDef.id, fields };
    this.definitions.set(key, def);
    return def;
  }

  private async definitionForClassRef(
    url: URL,
    mod: ModuleSyntax,
    ref: ClassReference,
    targetRef: CardRef
  ): Promise<CardDefinition | undefined> {
    if (ref.type === "internal") {
      return await this.buildDefinition(
        url,
        mod,
        targetRef,
        mod.possibleCards[ref.classIndex]
      );
    } else {
      if (this.isLocal(new URL(ref.module, url))) {
        if (
          baseRealm.fileURL(ref.module).href === `${baseRealm.url}card-api` &&
          ref.name === "Card"
        ) {
          let { module, name } = ref;
          return this.definitions.get(
            internalKeyFor({ module, name, type: "exportedCard" }, url)
          );
        }
        let inner = this.lookupPossibleCard(new URL(ref.module, url), ref.name);
        if (!inner) {
          return undefined;
        }
        return await this.buildDefinition(
          new URL(ref.module, url),
          inner.mod,
          targetRef,
          inner.possibleCard
        );
      } else {
        return await this.getExternalCardDefinition(new URL(ref.module, url), {
          type: "exportedCard",
          name: ref.name,
          module: ref.module,
        });
      }
    }
  }

  // TODO I think this needs to recurse into visit file in the situation where
  // the card we are looking up hasn't been analyzed yet
  private lookupPossibleCard(
    module: URL,
    exportedName: string
  ): { mod: ModuleSyntax; possibleCard: PossibleCardClass } | undefined {
    let mod = this.modules.get(module);
    if (!mod) {
      // TODO: broken import seems bad
      return undefined;
    }
    let possibleCard = mod.possibleCards.find(
      (c) => c.exportedAs === exportedName
    );
    if (!possibleCard) {
      return undefined;
    }
    return { mod, possibleCard };
  }

  private isLocal(url: URL): boolean {
    return url.href.startsWith(this.realm.url);
  }

  public async getExternalCardDefinition(
    moduleURL: URL,
    ref: CardRef
  ): Promise<CardDefinition | undefined> {
    let key = internalKeyFor(ref, undefined); // these should always be absolute URLs
    let promise = this.#externalDefinitionsCache.get(key);
    if (promise) {
      return await promise;
    }
    let deferred = new Deferred<CardDefinition | undefined>();
    this.#externalDefinitionsCache.set(key, deferred.promise);

    let url = `${moduleURL.href}/_typeOf?${stringify(ref)}`;
    let response = await Loader.fetch(url, {
      headers: {
        Accept: "application/vnd.api+json",
      },
    });
    if (!response.ok) {
      console.log(`Could not get card type for ${url}: ${response.status}`);
      deferred.fulfill(undefined);
      return undefined;
    }

    let resource: CardDefinitionResource = (await response.json()).data;
    let def: CardDefinition = {
      id: resource.attributes.cardRef,
      key: resource.id,
      super: resource.relationships._super?.meta.ref,
      fields: new Map(
        Object.entries(resource.relationships)
          .filter(([fieldName]) => fieldName !== "_super")
          .map(([fieldName, fieldInfo]) => [
            fieldName,
            {
              fieldType: fieldInfo.meta.type as "contains" | "containsMany",
              fieldCard: fieldInfo.meta.ref,
            },
          ])
      ),
    };
    deferred.fulfill(def);
    return def;
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
}

function removeCardsInURL(url: URL, definition: Map<string, CardDefinition>) {
  for (let key of definition.keys()) {
    if (key.startsWith(url.href)) {
      definition.delete(key);
    }
  }
}

function maybeRemoveModules(url: URL, modules: URLMap<ModuleSyntax>) {
  modules.remove(url);
  modules.remove(trimExecutableExtension(url));
}

export class SearchIndex {
  // TODO find a new home for exportedCardRefs
  // private exportedCardRefs = new Map<string, Map<string, ExportedCardRef>>();
  #current: CurrentRun;

  constructor(
    private realm: Realm,
    private readdir: (
      path: string
    ) => AsyncGenerator<{ name: string; path: string; kind: Kind }, void>,
    private readFileAsText: (
      path: LocalPath
    ) => Promise<{ content: string; lastModified: number } | undefined>
  ) {
    this.#current = CurrentRun.empty(realm);
  }

  async run() {
    this.#current = await CurrentRun.fromScratch(this.realm, {
      readdir: this.readdir,
      readFileAsText: this.readFileAsText,
    });
  }

  async update(url: URL, opts?: { delete?: true }): Promise<void> {
    this.#current = await CurrentRun.incremental(
      url,
      opts?.delete ? "delete" : "update",
      this.#current
    );
    // await this.visitFile(url, opts);
    // await this.semanticPhase();
  }

  public isIgnored(url: URL): boolean {
    return this.#current.isIgnored(url);
  }

  private async getExternalCardDefinition(
    moduleURL: URL,
    ref: CardRef
  ): Promise<CardDefinition | undefined> {
    return await this.#current.getExternalCardDefinition(moduleURL, ref);
  }

  private async semanticPhase(): Promise<void> {
    let newDefinitions: Map<string, CardDefinition> = new Map([
      // seed the definitions with the base card
      [
        internalKeyFor(
          {
            type: "exportedCard",
            module: `${baseRealm.url}card-api`,
            name: "Card",
          },
          undefined
        ),
        {
          id: {
            type: "exportedCard",
            module: `${baseRealm.url}card-api`,
            name: "Card",
          },
          key: internalKeyFor(
            {
              type: "exportedCard",
              module: `${baseRealm.url}card-api`,
              name: "Card",
            },
            undefined
          ),
          super: undefined,
          fields: new Map(),
        },
      ],
    ]);
    for (let [url, mod] of this.modules) {
      for (let possibleCard of mod.possibleCards) {
        if (possibleCard.exportedAs) {
          if (this.isIgnored(url)) {
            continue;
          }
          await this.buildDefinition(
            newDefinitions,
            url,
            mod,
            {
              type: "exportedCard",
              module: url.href,
              name: possibleCard.exportedAs,
            },
            possibleCard
          );
        }
      }
    }

    // using a map of a map so we have a uniqueness guarantee on the card refs
    // via the interior map keys so we don't end up with dupe refs
    let newExportedCardRefs = new Map<string, Map<string, ExportedCardRef>>();
    for (let def of newDefinitions.values()) {
      if (def.id.type !== "exportedCard") {
        continue;
      }
      let { module } = def.id;
      let refsMap = newExportedCardRefs.get(module);
      if (!refsMap) {
        refsMap = new Map();
        newExportedCardRefs.set(module, refsMap);
      }
      let { type: remove, ...exportedCardRef } = def.id;
      refsMap.set(internalKeyFor(def.id, undefined), exportedCardRef);
    }

    // atomically update the search index
    this.definitions = newDefinitions;
    this.exportedCardRefs = newExportedCardRefs;

    // once we have definitions we can fill in the instance types
    for (let [url, entry] of [...this.instances]) {
      entry.types = await this.getTypes(entry.resource.meta.adoptsFrom, url);
    }
  }

  async search(query: Query): Promise<CardResource[]> {
    let matcher = await this.buildMatcher(query.filter, {
      module: `${baseRealm.url}card-api`,
      name: "Card",
    });

    return [...this.#current.instances.values()]
      .filter(matcher)
      .sort(this.buildSorter(query.sort))
      .map((entry) => entry.resource);
  }

  async typeOf(
    ref: CardRef,
    relativeTo = new URL(this.realm.url)
  ): Promise<CardDefinition | undefined> {
    let def = this.#current.definitions.get(internalKeyFor(ref, relativeTo));
    if (def) {
      return def;
    }
    let { module } = getExportedCardContext(ref);
    let moduleURL = new URL(module, relativeTo);
    if (!this.realm.paths.inRealm(moduleURL)) {
      return await this.getExternalCardDefinition(moduleURL, ref);
    }
    return undefined;
  }

  async exportedCardsOf(module: string): Promise<ExportedCardRef[]> {
    module = trimExecutableExtension(new URL(module, this.realm.url)).href;
    let refsMap = this.exportedCardRefs.get(module);
    if (!refsMap) {
      return [];
    }
    return [...refsMap.values()];
  }

  async card(url: URL): Promise<CardResource | undefined> {
    return this.#current.instances.get(url)?.resource;
  }

  private async getTypes(
    ref: ExportedCardRef,
    relativeTo = new URL(ref.module)
  ): Promise<string[]> {
    let fullRef: CardRef | undefined = { type: "exportedCard", ...ref };
    let types: string[] = [];
    while (fullRef) {
      let def: CardDefinition | undefined = await this.typeOf(
        fullRef,
        relativeTo
      );
      if (!def) {
        // TODO: create a way to report this error without breaking indexing
        throw new Error(
          `Tried to getTypes of ${JSON.stringify(
            ref
          )} but couldn't find that definition`
        );
      }
      types.push(internalKeyFor(fullRef, relativeTo));
      fullRef = def.super;
    }
    return types;
  }

  private cardHasType(entry: SearchEntry, ref: CardRef): boolean {
    return Boolean(
      entry.types?.find((t) => t === internalKeyFor(ref, undefined)) // assumes ref refers to absolute module URL
    );
  }

  private buildSorter(
    expressions: Sort | undefined
  ): (e1: SearchEntry, e2: SearchEntry) => number {
    if (!expressions || expressions.length === 0) {
      return () => 0;
    }
    let sorters = expressions.map(({ by, on, direction }) => {
      return (e1: SearchEntry, e2: SearchEntry) => {
        let ref: CardRef = { type: "exportedCard", ...on };
        if (!this.cardHasType(e1, ref)) {
          return direction === "desc" ? -1 : 1;
        }
        if (!this.cardHasType(e2, ref)) {
          return direction === "desc" ? 1 : -1;
        }
        let a = e1.searchData[by];
        let b = e2.searchData[by];
        if (a === undefined) {
          return direction === "desc" ? -1 : 1; // if descending, null position is before the rest
        }
        if (b === undefined) {
          return direction === "desc" ? 1 : -1; // `a` is not null
        }
        // TODO: use queryableValue check here
        if (a < b) {
          return direction === "desc" ? 1 : -1;
        } else if (a > b) {
          return direction === "desc" ? -1 : 1;
        } else {
          return 0;
        }
      };
    });

    return (e1: SearchEntry, e2: SearchEntry) => {
      for (let sorter of sorters) {
        let result = sorter(e1, e2);
        if (result !== 0) {
          return result;
        }
      }
      return 0;
    };
  }

  // Matchers are three-valued (true, false, null) because a query that talks
  // about a field that is not even present on a given card results in `null` to
  // distinguish it from a field that is present but not matching the filter
  // (`false`)
  private async buildMatcher(
    filter: Filter | undefined,
    onRef: ExportedCardRef
  ): Promise<(entry: SearchEntry) => boolean | null> {
    if (!filter) {
      return (_entry) => true;
    }

    if ("type" in filter) {
      let ref: CardRef = { type: "exportedCard", ...filter.type };
      await this.strictTypeOf(ref);
      return (entry) => this.cardHasType(entry, ref);
    }

    let on = filter?.on ?? onRef;

    if ("any" in filter) {
      let matchers = await Promise.all(
        filter.any.map((f) => this.buildMatcher(f, on))
      );
      return (entry) => some(matchers, (m) => m(entry));
    }

    if ("every" in filter) {
      let matchers = await Promise.all(
        filter.every.map((f) => this.buildMatcher(f, on))
      );
      return (entry) => every(matchers, (m) => m(entry));
    }

    if ("not" in filter) {
      let matcher = await this.buildMatcher(filter.not, on);
      return (entry) => {
        let inner = matcher(entry);
        if (inner == null) {
          // irrelevant cards stay irrelevant, even when the query is inverted
          return null;
        } else {
          return !inner;
        }
      };
    }

    if ("eq" in filter) {
      let ref: CardRef = { type: "exportedCard", ...on };

      await Promise.all(
        Object.keys(filter.eq).map((fieldPath) =>
          this.validateField(ref, fieldPath.split("."))
        )
      );

      return (entry) =>
        every(Object.entries(filter.eq), ([fieldPath, queryVal]) => {
          if (this.cardHasType(entry, ref)) {
            let value = entry.searchData[fieldPath];
            if (value === undefined && queryVal != null) {
              return null;
            }
            return value == queryVal;
          } else {
            return null;
          }
        });
    }

    if ("range" in filter) {
      let ref: CardRef = { type: "exportedCard", ...on };

      await Promise.all(
        Object.keys(filter.range).map((fieldPath) =>
          this.validateField(ref, fieldPath.split("."))
        )
      );

      return (entry) =>
        every(Object.entries(filter.range), ([fieldPath, range]) => {
          if (this.cardHasType(entry, ref)) {
            let value = entry.searchData[fieldPath];
            if (value === undefined) {
              return null;
            }
            if (
              (range.gt && !(value > range.gt)) ||
              (range.lt && !(value < range.lt)) ||
              (range.gte && !(value >= range.gte)) ||
              (range.lte && !(value <= range.lte))
            ) {
              return false;
            }
            return true;
          }
          return null;
        });
    }

    throw new Error("Unknown filter");
  }

  private async strictTypeOf(ref: CardRef): Promise<CardDefinition> {
    let def = await this.typeOf(ref);
    let { module, name } = ref as ExportedCardRef;
    if (!def) {
      throw new Error(
        `Your filter refers to nonexistent type: import ${
          name === "default" ? "default" : `{ ${name} }`
        } from "${module}"`
      );
    }
    return def;
  }

  private async validateField(
    ref: CardRef,
    fieldPathSegments: string[]
  ): Promise<void> {
    let def = await this.strictTypeOf(ref);
    let first = fieldPathSegments.shift()!;
    let nextRef = def.fields.get(first);
    if (!nextRef) {
      throw new Error(
        `Your filter refers to nonexistent field "${first}" on type ${internalKeyFor(
          ref,
          undefined // assumes absolute module URL
        )}`
      );
    }
    if (fieldPathSegments.length > 0) {
      return await this.validateField(nextRef.fieldCard, fieldPathSegments);
    }
  }
}

function isOurFieldDecorator(ref: ClassReference, inModule: URL): boolean {
  return (
    ref.type === "external" &&
    new URL(ref.module, inModule).href === baseRealm.fileURL("card-api").href &&
    ref.name === "field"
  );
}

function internalKeyFor(ref: CardRef, relativeTo: URL | undefined): string {
  switch (ref.type) {
    case "exportedCard":
      let module = trimExecutableExtension(
        new URL(ref.module, relativeTo)
      ).href;
      return `${module}/${ref.name}`;
    case "ancestorOf":
      return `${internalKeyFor(ref.card, relativeTo)}/ancestor`;
    case "fieldOf":
      return `${internalKeyFor(ref.card, relativeTo)}/fields/${ref.field}`;
  }
}

function getFieldType(
  ref: ClassReference,
  inModule: URL
): "contains" | "containsMany" | undefined {
  if (
    ref.type === "external" &&
    new URL(ref.module, inModule).href === baseRealm.fileURL("card-api").href &&
    ["contains", "containsMany"].includes(ref.name)
  ) {
    return ref.name as ReturnType<typeof getFieldType>;
  }
  return undefined;
}

// three-valued version of Array.every that propagates nulls. Here, the presence
// of any nulls causes the whole thing to be null.
function every<T>(
  list: T[],
  predicate: (t: T) => boolean | null
): boolean | null {
  let result = true;
  for (let element of list) {
    let status = predicate(element);
    if (status == null) {
      return null;
    }
    result = result && status;
  }
  return result;
}

// three-valued version of Array.some that propagates nulls. Here, the whole
// expression becomes null only if the whole input is null.
function some<T>(
  list: T[],
  predicate: (t: T) => boolean | null
): boolean | null {
  let result = null;
  for (let element of list) {
    let status = predicate(element);
    if (status === true) {
      return true;
    }
    if (status === false) {
      result = false;
    }
  }
  return result;
}
