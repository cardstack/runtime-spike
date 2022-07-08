import { RealmAdapter, Kind, FileRef } from '@cardstack/runtime-common';
// import { CardError } from '@cardstack/runtime-common/error';
import { traverse } from './file-system';

export class LocalRealm implements RealmAdapter {
  constructor(private fs: FileSystemDirectoryHandle) {}

  async *readdir(
    path: string,
    opts?: { create?: true }
  ): AsyncGenerator<{ name: string; path: string; kind: Kind }, void> {
    let dirHandle = isTopPath(path)
      ? this.fs
      : await traverse(this.fs, path, 'directory', opts);
    for await (let [name, handle] of dirHandle as unknown as AsyncIterable<
      [string, FileSystemDirectoryHandle | FileSystemFileHandle]
    >) {
      // note that the path of a directory always ends in "/"
      let innerPath = isTopPath(path) ? name : `${path}${name}`;
      yield { name, path: innerPath, kind: handle.kind };
    }
  }

  async openFile(path: string): Promise<FileRef | undefined> {
    try {
      let fileHandle = await traverse(this.fs, path, 'file');
      let file = await fileHandle.getFile();
      let lazyContent: ReadableStream<Uint8Array> | null = null;
      return {
        path,
        get content() {
          if (!lazyContent) {
            lazyContent =
              file.stream() as unknown as ReadableStream<Uint8Array>;
          }
          return lazyContent;
        },
        lastModified: file.lastModified,
      };
    } catch (err) {
      console.log(`${err.name}: "${path}"`);
      // if (!(err instanceof CardError) || err.response.status !== 404) {
      //   throw err;
      // }
      return undefined;
    }
  }

  async write(
    path: string,
    contents: string
  ): Promise<{ lastModified: number }> {
    let handle = await traverse(this.fs, path, 'file', { create: true });
    // TypeScript seems to lack types for the writable stream features
    let stream = await (handle as any).createWritable();
    await stream.write(contents);
    await stream.close();
    let { lastModified } = await handle.getFile();
    return { lastModified };
  }
}

function isTopPath(path: string): boolean {
  return path === '';
}
