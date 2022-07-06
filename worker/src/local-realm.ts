import {
  RealmAdapter,
  Kind,
  executableExtensions,
} from '@cardstack/runtime-common';
import { traverse } from './file-system';
import { getLocalFileWithFallbacks, serveLocalFile } from './file-system';
import { readFileAsText } from './util';

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

  async openFile(path: string): Promise<ReadableStream<Uint8Array>> {
    let fileHandle = await traverse(this.fs, path, 'file');
    let file = await fileHandle.getFile();
    return file.stream() as unknown as ReadableStream<Uint8Array>;
  }

  async statFile(path: string): Promise<{ lastModified: number }> {
    let fileHandle = await traverse(this.fs, path, 'file');
    let file = await fileHandle.getFile();
    let { lastModified } = file;
    return { lastModified };
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

  async todoHandle(
    url: URL,
    makeJS: (content: string, debugFilename: string) => Promise<Response>
  ) {
    let handle = await getLocalFileWithFallbacks(
      this.fs,
      url.pathname.slice(1),
      executableExtensions
    );
    if (
      executableExtensions.some((extension) => handle.name.endsWith(extension))
    ) {
      let content = await readFileAsText(handle);
      return await makeJS(content, handle.name);
    } else {
      return await serveLocalFile(handle);
    }
  }

  async todo2(url: URL) {
    let handle = await getLocalFileWithFallbacks(
      this.fs,
      url.pathname.slice(1),
      executableExtensions
    );
    let pathSegments = url.pathname.split('/');
    let requestedName = pathSegments.pop()!;
    if (handle.name !== requestedName) {
      return new Response(null, {
        status: 302,
        headers: {
          Location: [...pathSegments, handle.name].join('/'),
        },
      });
    }
    return await serveLocalFile(handle);
  }
}

function isTopPath(path: string): boolean {
  return path === '';
}
