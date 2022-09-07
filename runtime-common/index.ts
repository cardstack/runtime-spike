export interface CardJSON {
  data: {
    attributes?: Record<string, any>;
    // TODO add relationships
    meta: {
      adoptsFrom: {
        module: string;
        name: string;
      };
    };
  };
  // TODO add included
}

export { Deferred } from "./deferred";

export interface ResourceObject {
  type: string;
  attributes?: Record<string, any>;
  relationships?: Record<string, any>;
  meta?: Record<string, any>;
}

export interface ResourceObjectWithId extends ResourceObject {
  id: string;
}

export interface DirectoryEntryRelationship {
  links: {
    related: string;
  };
  meta: {
    kind: "directory" | "file";
  };
}
import { RealmPaths } from "./paths";
import { Query } from "./query";
export const baseRealm = new RealmPaths("https://cardstack.com/base/");
export { RealmPaths };

export const executableExtensions = [".js", ".gjs", ".ts", ".gts"];

import type { ExportedCardRef } from "./search-index";
export const catalogEntryRef: ExportedCardRef = {
  module: "https://cardstack.com/base/catalog-entry",
  name: "CatalogEntry",
};

type Format = "isolated" | "embedded" | "edit";
export interface NewCardArgs {
  type: "new";
  realmURL: string;
  cardSource: ExportedCardRef;
  initialAttributes?: CardJSON["data"]["attributes"];
}
export interface ExistingCardArgs {
  type: "existing";
  url: string;
  // this is just used for test fixture data. as soon as we
  // have an actual ember service for the API we should just
  //  mock that instead
  json?: CardJSON;
  format?: Format;
}

// From https://github.com/iliakan/detect-node
export const isNode =
  Object.prototype.toString.call(globalThis.process) === "[object process]";

/* Any new externally consumed modules should be added here,
 * along with the exports from the modules that are consumed.
 * These exports are paired with the host/app/app.ts which is
 * responsible for loading the external modules and making them
 * available in the window.RUNTIME_SPIKE_EXTERNALS Map. Any changes
 * to the externals below should also be reflected in the
 * host/app/app.ts file.
 */

export const externalsMap: Map<string, string[]> = new Map([
  ["@cardstack/runtime-common", ["Loader", "chooseCard"]],
  ["@glimmer/component", ["default"]],
  ["@ember/component", ["setComponentTemplate", "default"]],
  ["@ember/component/template-only", ["default"]],
  ["@ember/template-factory", ["createTemplateFactory"]],
  ["@glimmer/tracking", ["tracked"]],
  ["@ember/object", ["action", "get"]],
  ["@ember/helper", ["get", "fn"]],
  ["@ember/modifier", ["on"]],
  ["@ember/destroyable", ["registerDestructor"]],
  ["ember-resources", ["Resource", "useResource"]],
  ["ember-concurrency", ["task", "restartableTask"]],
  ["ember-concurrency-ts", ["taskFor"]],
  ["ember-modifier", ["default"]],
  ["lodash", ["flatMap", "startCase", "get"]],
  ["tracked-built-ins", ["TrackedWeakMap"]],
  ["date-fns", ["parseISO", "format", "parse"]],
  ["@ember/service", ["default", "service"]],
  ["@ember/routing", ["default"]],
]);

export function isCardJSON(json: any): json is CardJSON {
  if (typeof json !== "object" || !("data" in json)) {
    return false;
  }
  let { data } = json;
  if (typeof data !== "object") {
    return false;
  }

  let { meta, attributes } = data;
  if (
    typeof meta !== "object" ||
    ("attributes" in data && typeof attributes !== "object")
  ) {
    return false;
  }

  if (!("adoptsFrom" in meta)) {
    return false;
  }

  let { adoptsFrom } = meta;
  if (typeof adoptsFrom !== "object") {
    return false;
  }
  if (!("module" in adoptsFrom) || !("name" in adoptsFrom)) {
    return false;
  }

  let { module, name } = adoptsFrom;
  return typeof module === "string" && typeof name === "string";
}

export { Realm } from "./realm";
export { Loader } from "./loader";
export type { Kind, RealmAdapter, FileRef } from "./realm";

export type {
  CardRef,
  ExportedCardRef,
  CardResource,
  CardDocument,
  CardDefinition,
} from "./search-index";
export { isCardResource, isCardDocument } from "./search-index";

import type { Card } from "https://cardstack.com/base/card-api";

export interface CardChooser {
  chooseCard<T extends Card>(query: Query): Promise<undefined | T>;
}

export async function chooseCard<T extends Card>(
  query: Query
): Promise<undefined | T> {
  let here = globalThis as any;
  if (!here._CARDSTACK_CARD_CHOOSER) {
    throw new Error(
      `no cardstack card chooser is available in this environment`
    );
  }
  let chooser: CardChooser = here._CARDSTACK_CARD_CHOOSER;

  return await chooser.chooseCard<T>(query);
}
