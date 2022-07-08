import { executableExtensions, baseRealm } from ".";
import { Kind } from "./realm";
import { RealmPaths } from "./paths";
import { ModuleSyntax } from "./module-syntax";
import { ClassReference, PossibleCardClass } from "./schema-analysis-plugin";
// import ignore, { Ignore } from "ignore";

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

type Query = unknown;

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
  constructor(mapTuple: [key: URL, value: T][] = []) {
    this.#map = new Map(mapTuple.map(([key, value]) => [key.href, value]));
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
}

export class SearchIndex {
  private instances = new URLMap<CardResource>();
  private modules = new URLMap<ModuleSyntax>();
  private directories = new URLMap<{ name: string; kind: Kind }[]>();
  private definitions = new Map<string, CardDefinition>();
  private exportedCardRefs = new Map<string, CardRef[]>();
  // private ignoreMap = new URLMap<Ignore>();

  constructor(
    private realm: RealmPaths,
    private readdir: (
      path: string
    ) => AsyncGenerator<{ name: string; path: string; kind: Kind }, void>,
    private readFileAsText: (path: string) => Promise<string>
  ) {}

  async run() {
    let newDirectories = new URLMap<{ name: string; kind: Kind }[]>();
    await this.visitDirectory(new URL(this.realm.url), newDirectories);
    await this.semanticPhase(newDirectories);
  }

  private async visitDirectory(
    url: URL,
    directories: URLMap<{ name: string; kind: Kind }[]>
  ): Promise<void> {
    // TODO we should be using ignore patterns for the current context so the
    // ignores are consistent with the index, i.e. don't use ignore file from a
    // previous search index run on a new search index

    // TODO: ignorePatterns
    // let ignorePatterns = await this.getIgnorePatterns(url);
    // if (ignorePatterns) {
    //   this.ignoreMap.set(url, ignore().add(ignorePatterns));
    // }

    let entries = directories.get(url);
    if (!entries) {
      entries = [];
      directories.set(url, entries);
    }
    for await (let { path: innerPath, kind } of this.readdir(
      this.realm.local(url)
    )) {
      let innerURL = new URL(innerPath, this.realm.url);
      // if (this.isIgnored(innerURL)) {
      //   return;
      // }

      let name = innerPath.split("/").pop()!;
      if (kind === "file") {
        entries.push({ name, kind: "file" });
        await this.visitFile(innerURL);
      } else {
        entries.push({ name, kind: "directory" });
        innerURL = assertURLEndsWithSlash(innerURL);
        await this.visitDirectory(innerURL, directories);
      }
    }
  }

  async update(url: URL, opts?: { delete?: true }): Promise<void> {
    await this.visitFile(url);

    let newDirectories = new URLMap([...this.directories]);
    let segments = url.href.split("/");
    let name = segments.pop()!;
    let dirURL = new URL(segments.join("/") + "/");

    if (opts?.delete) {
      let entries = newDirectories.get(dirURL);
      if (entries) {
        let index = entries.findIndex((e) => e.name === name);
        if (index > -1) {
          entries.splice(index, 1);
        }
      }
    } else {
      let entries = newDirectories.get(dirURL);
      if (!entries) {
        entries = [];
        newDirectories.set(dirURL, entries);
      }
      if (!entries.find((e) => e.name === name)) {
        entries.push({ name, kind: "file" });
      }
    }
    await this.semanticPhase(newDirectories);
  }

  private async visitFile(url: URL) {
    if (url.href.endsWith(".json")) {
      let json = JSON.parse(await this.readFileAsText(this.realm.local(url)));
      if (isCardDocument(json)) {
        let instanceURL = new URL(url.href.replace(/\.json$/, ""));
        json.data.id = instanceURL.href;
        this.instances.set(instanceURL, json.data);
      }
    } else if (hasExecutableExtension(url.href)) {
      let mod = new ModuleSyntax(
        await this.readFileAsText(this.realm.local(url))
      );
      this.modules.set(url, mod);
      this.modules.set(trimExecutableExtension(url), mod);
    }
  }

  private async semanticPhase(
    directories?: URLMap<{ name: string; kind: Kind }[]>
  ): Promise<void> {
    let newDefinitions: Map<string, CardDefinition> = new Map();
    for (let [path, mod] of this.modules) {
      for (let possibleCard of mod.possibleCards) {
        if (possibleCard.exportedAs) {
          await this.buildDefinition(
            newDefinitions,
            path,
            mod,
            {
              type: "exportedCard",
              module: path.href,
              name: possibleCard.exportedAs,
            },
            possibleCard
          );
        }
      }
    }
    let newExportedCardRefs = new Map<string, CardRef[]>();
    for (let def of newDefinitions.values()) {
      if (def.id.type !== "exportedCard") {
        continue;
      }
      let { module } = def.id;
      let refs = newExportedCardRefs.get(module);
      if (!refs) {
        refs = [];
        newExportedCardRefs.set(module, refs);
      }
      refs.push(def.id);
    }

    // atomically update the search index
    this.definitions = newDefinitions;
    this.exportedCardRefs = newExportedCardRefs;
    if (directories) {
      this.directories = directories;
    }
  }

  private async buildDefinition(
    definitions: Map<string, CardDefinition>,
    url: URL,
    mod: ModuleSyntax,
    ref: CardRef,
    possibleCard: PossibleCardClass
  ): Promise<CardDefinition | undefined> {
    let id: CardRef = possibleCard.exportedAs
      ? {
          type: "exportedCard",
          module: new URL(url, this.realm.url).href,
          name: possibleCard.exportedAs,
        }
      : ref;

    let def = definitions.get(this.internalKeyFor(id));
    if (def) {
      definitions.set(this.internalKeyFor(ref), def);
      return def;
    }

    let superDef = await this.definitionForClassRef(
      definitions,
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
        definitions,
        url,
        mod,
        possibleField.card,
        { type: "fieldOf", card: id, field: fieldName }
      );
      if (fieldDef) {
        fields.set(fieldName, { fieldType, fieldCard: fieldDef.id });
      }
    }

    let key = this.internalKeyFor(id);
    def = { id, key, super: superDef.id, fields };
    definitions.set(key, def);
    return def;
  }

  private async definitionForClassRef(
    definitions: Map<string, CardDefinition>,
    url: URL,
    mod: ModuleSyntax,
    ref: ClassReference,
    targetRef: CardRef
  ): Promise<CardDefinition | undefined> {
    if (ref.type === "internal") {
      return await this.buildDefinition(
        definitions,
        url,
        mod,
        targetRef,
        mod.possibleCards[ref.classIndex]
      );
    } else {
      if (this.isLocal(new URL(ref.module, url))) {
        let inner = this.lookupPossibleCard(new URL(ref.module, url), ref.name);
        if (!inner) {
          return undefined;
        }
        return await this.buildDefinition(
          definitions,
          new URL(ref.module, url),
          inner.mod,
          targetRef,
          inner.possibleCard
        );
      } else {
        return await this.getExternalCardDefinition(ref.module, ref.name);
      }
    }
  }

  private internalKeyFor(ref: CardRef): string {
    switch (ref.type) {
      case "exportedCard":
        let module = new URL(ref.module, this.realm.url).href;
        return `${module}/${ref.name}`;
      case "ancestorOf":
        return `${this.internalKeyFor(ref.card)}/ancestor`;
      case "fieldOf":
        return `${this.internalKeyFor(ref.card)}/fields/${ref.field}`;
    }
  }

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

  private async getExternalCardDefinition(
    href: string,
    exportName: string
  ): Promise<CardDefinition | undefined> {
    // TODO This is scaffolding for the base realm, implement for real once we
    // have this realm endpoint fleshed out
    let module = href.startsWith("http:") ? href : `http:${href}`;
    let moduleURL = new URL(module);
    if (!baseRealm.inRealm(moduleURL)) {
      return Promise.resolve(undefined);
    }
    let path = baseRealm.local(moduleURL);
    switch (path) {
      case "card-api":
        return exportName === "Card"
          ? {
              id: {
                type: "exportedCard",
                module: href,
                name: exportName,
              },
              key: `${baseRealm.fileURL(path)}/Card`,
              super: undefined,
              fields: new Map(),
            }
          : undefined;
      case "string":
      case "integer":
      case "date":
      case "datetime":
        return exportName === "default"
          ? {
              id: {
                type: "exportedCard",
                module: href,
                name: exportName,
              },
              super: {
                type: "exportedCard",
                module: baseRealm.fileURL("card-api").href,
                name: "Card",
              },
              key: `${baseRealm.fileURL(path)}/default`,
              fields: new Map(),
            }
          : undefined;
      case "/base/text-area":
        return exportName === "default"
          ? Promise.resolve({
              id: {
                type: "exportedCard",
                module: href,
                name: exportName,
              },
              super: {
                type: "exportedCard",
                module: baseRealm.fileURL("string").href,
                name: "default",
              },
              key: `${baseRealm.fileURL(path)}/default`,
              fields: new Map(),
            })
          : undefined;
    }
    throw new Error(
      `unimplemented: don't know how to look up card types for ${href}`
    );
  }

  private isLocal(url: URL): boolean {
    return url.href.startsWith(this.realm.url);
  }

  // TODO: complete these types
  async search(_query: Query): Promise<CardResource[]> {
    return [...this.instances.values()];
  }

  async typeOf(ref: CardRef): Promise<CardDefinition | undefined> {
    return this.definitions.get(this.internalKeyFor(ref));
  }

  async exportedCardsOf(module: string): Promise<CardRef[]> {
    module = new URL(module, this.realm.url).href;
    return this.exportedCardRefs.get(module) ?? [];
  }

  // TODO merge this into the .search() API after we get the queries working
  async directory(
    url: URL
  ): Promise<{ name: string; kind: Kind }[] | undefined> {
    return this.directories.get(url);
  }
  // TODO merge this into the .search() API after we get the queries working
  async card(url: URL): Promise<CardResource | undefined> {
    return this.instances.get(url);
  }

  // TODO merge this into the .search() API after we get the queries working
  async module(url: URL): Promise<string | undefined> {
    return this.modules.get(url)?.src;
  }

  // private async getIgnorePatterns(url: URL): Promise<string | undefined> {
  //   try {
  //     return await this.readFileAsText(new URL(".monacoignore", url).pathname);
  //   } catch (e: any) {
  //     if (e.name !== "NotFoundError" && e.name !== "TypeMismatchError") {
  //       throw e;
  //     }
  //     try {
  //       return await this.readFileAsText(new URL(".gitignore", url).pathname);
  //     } catch (e: any) {
  //       if (e.name !== "NotFoundError" && e.name !== "TypeMismatchError") {
  //         throw e;
  //       }
  //     }
  //   }
  //   return undefined;
  // }

  // private isIgnored(url: URL): boolean {
  //   if (this.ignoreMap.size === 0) {
  //     return false;
  //   }
  //   // Test URL against closest ignore. (Should the ignores cascade? so that the
  //   // child ignore extends the parent ignore?)
  //   let ignoreURLs = [...this.ignoreMap.keys()].map((u) => u.href);
  //   let matchingIgnores = ignoreURLs.filter((u) => url.href.includes(u));
  //   let ignoreURL = matchingIgnores.sort((a, b) => b.length - a.length)[0] as
  //     | string
  //     | undefined;
  //   if (!ignoreURL) {
  //     return false;
  //   }

  //   let ignore = this.ignoreMap.get(new URL(ignoreURL))!;
  //   return ignore.test(url.pathname).ignored;
  // }
}

function isOurFieldDecorator(ref: ClassReference, inModule: URL): boolean {
  return (
    ref.type === "external" &&
    new URL(ref.module, inModule).href === baseRealm.fileURL("card-api").href &&
    ref.name === "field"
  );
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

function assertURLEndsWithSlash(url: URL): URL {
  if (url.href.endsWith("/")) {
    return url;
  }
  return new URL(url.href + "/");
}
