import {
  Query,
  CardResource,
  CardRef,
  CardDefinition,
  Unsaved,
} from "./search-index";

export class Realm {
  constructor(readonly url: string) {}

  // GET http://my-realm/cardstack/search
  async search(_query: Query): Promise<CardResource[]> {
    throw new Error("unimplemented");
  }

  // GET http://my-realm/cardstack/typeOf
  async typeOf(_ref: CardRef): Promise<CardDefinition | undefined> {
    throw new Error("unimplemented");
  }

  // GET http://my-realm/some/path
  // Accept: application/vnd.card+source
  async rawReadFile(
    _path: string
  ): Promise<{ content: string } | { redirect: string }> {
    // does executable extension fallback, does not transpile anything
    throw new Error("unimplemented");
  }

  // GET http://my-realm/some/path
  async readFile(_path: string): Promise<string> {
    // does executable extension fallback, transpiles JS when there's an executable extension
    throw new Error("unimplemented");
  }

  // POST http://my-realm/some/path
  async writeFile(_path: string, _content: string): Promise<void> {}

  // DELETE http://my-realm/some/path
  async deleteFile(_path: string): Promise<void> {}

  // GET http://my-realm/some/path/ (<- trailing slash significant)
  // Accept: application/vnd.api+json
  async readDir(_path: string): Promise<{ kind: string; name: string }[]> {
    throw new Error("unimplemented");
  }

  // GET http://my-realm/some/path (<- no trailing slash, no .json)
  // Accept: application/vnd.api+json
  async readCard(_path: string): Promise<CardResource> {
    throw new Error("unimplemented");
  }

  // POST http://my-realm/
  async createCard(
    _path: string,
    _resource: CardResource<Unsaved>
  ): Promise<CardResource> {
    throw new Error("unimplemented");
  }

  // PATCH http://my-realm/some/path
  async updateCard(
    _path: string,
    _resource: CardResource<Unsaved>
  ): Promise<CardResource> {
    throw new Error("unimplemented");
  }

  // DELETE http://my-realm/some/path
  async deleteCard(_path: string): Promise<void> {}
}
