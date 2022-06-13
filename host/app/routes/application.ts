import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';

export default class Application extends Route<{
  path: string | undefined;
  source: string | undefined;
  url: string | undefined;
}> {
  queryParams = {
    path: {
      refreshModel: true,
    },
  };

  @service declare router: RouterService;

  async model(args: { path: string | undefined }) {
    let { path } = args;
    if (!path) {
      return { path: undefined, source: undefined, url: undefined };
    }

    let url = `http://local-realm/sources/${path}`;
    let response = await fetch(url);
    if (!response.ok) {
      // TODO should we have an error route?
      console.error(
        `Could not load ${url}: ${response.status}, ${response.statusText}`
      );
      return { path, source: undefined, url: response.url };
    }

    // don't bother loading the source if we're about to redirect
    let source = url === response.url ? await response.text() : undefined;

    return { path, source, url: response.url };

    // TODO how to we deal with live loading of sources?
  }

  afterModel(model: {
    path: string | undefined;
    source: string | undefined;
    url: string | undefined;
  }) {
    let { path, url } = model;
    if (url && path) {
      let requestedUrl = `http://local-realm/sources/${path}`;
      if (requestedUrl !== url) {
        let path = new URL(url).pathname.replace(/^\/sources\//, '');
        this.router.transitionTo('application', { queryParams: { path } });
      }
    }
  }
}
