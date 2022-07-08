export class RealmPaths {
  readonly realm: string;

  constructor(realmURL: string | URL) {
    this.realm =
      (typeof realmURL === "string" ? realmURL : realmURL.href).replace(
        /\/$/,
        ""
      ) + "/";
  }

  local(url: URL): LocalPath {
    if (!url.href.startsWith(this.realm)) {
      throw new Error(`bug: realm ${this.realm} does not contain ${url.href}`);
    }
    // this will always remove a leading slash because our constructor ensures
    // this.#realm has a trailing slash.
    let local = url.href.slice(this.realm.length);

    if (local.endsWith("/")) {
      local.slice(-1);
    }
    return local;
  }

  fileURL(local: LocalPath): URL {
    return new URL(local, this.realm);
  }

  directoryURL(local: LocalPath): URL {
    return new URL(local + "/", this.realm);
  }

  inRealm(url: URL): boolean {
    return url.href.startsWith(this.realm);
  }
}

// Documenting that this represents a local path within realm, with no leading
// slashes or dots and no trailing slash. Example:
//
//    in realm http://example.com/my-realm/ url
//    http://example.com/my-realm/hello/world/ maps to local path "hello/world"
//
export type LocalPath = string;
