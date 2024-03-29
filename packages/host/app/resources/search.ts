import { Resource, useResource } from 'ember-resources';
import { restartableTask } from 'ember-concurrency';
import { taskFor } from 'ember-concurrency-ts';
import { tracked } from '@glimmer/tracking';
import { baseRealm } from '@cardstack/runtime-common';
import { Loader } from '@cardstack/runtime-common/loader';
import { service } from '@ember/service';
import LocalRealm from '../services/local-realm';
import flatMap from 'lodash/flatMap';
import { getOwner } from '@ember/application';
import type LoaderService from '../services/loader-service';
import type CardService from '../services/card-service';
import type { Query } from '@cardstack/runtime-common/query';
import type { Card } from 'https://cardstack.com/base/card-api';

interface Args {
  named: {
    query: Query;
    loader: Loader;
  };
}

export class Search extends Resource<Args> {
  @tracked instances: Card[] = [];
  @service declare localRealm: LocalRealm;
  @service declare cardService: CardService;

  constructor(owner: unknown, args: Args) {
    super(owner, args);
    let { query, loader } = args.named;
    taskFor(this.search).perform(query, loader);
  }

  @restartableTask private async search(query: Query, loader: Loader) {
    // until we have realm index rollup, search all the realms as separate
    // queries that we merge together
    this.instances = flatMap(
      await Promise.all(
        [this.localRealm.url.href, loader.resolve(baseRealm.url)].map(
          async (realm) => await this.cardService.search(query, realm)
        )
      )
    );
  }

  get isLoading() {
    return taskFor(this.search).isRunning;
  }
}

export function getSearchResults(parent: object, query: () => Query) {
  return useResource(parent, Search, () => ({
    named: {
      query: query(),
      loader: (
        (getOwner(parent) as any).lookup(
          'service:loader-service'
        ) as LoaderService
      ).loader,
    },
  }));
}
