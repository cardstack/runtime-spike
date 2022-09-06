import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import {
  catalogEntryRef,
  type ExportedCardRef,
  type CardResource,
} from '@cardstack/runtime-common';
import { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';

import { getSearchResults } from '../resources/search';

type State =
  | {
      name: 'empty';
      entries: undefined;
    }
  | {
      name: 'loading';
      entries: undefined;
    }
  | {
      name: 'loaded';
      entries: CardResource[];
    };

export default class Modal extends Service {
  @service declare router: RouterService;
  @tracked status: 'open' | 'closed' = 'closed';
  @tracked ref: ExportedCardRef | undefined = undefined;
  @tracked realmURL: string | undefined = undefined;

  catalogEntry = getSearchResults(
    this,
    () =>
      this.ref
        ? { filter: { on: catalogEntryRef, eq: { ref: this.ref } } }
        : { filter: { type: catalogEntryRef } },
    () => this.realmURL
  );

  get isShowing(): boolean {
    return this.status === 'open';
  }

  get state(): State {
    if (this.catalogEntry.isLoading) {
      return { name: 'loading', entries: undefined };
    } else if (this.catalogEntry.instances.length > 0) {
      return { name: 'loaded', entries: this.catalogEntry.instances };
    } else {
      return { name: 'empty', entries: undefined };
    }
  }

  @action open(ref?: ExportedCardRef, realmURL?: string): void {
    this.ref = ref;
    this.realmURL = realmURL;
    this.status = 'open';
  }

  @action close(): void {
    this.status = 'closed';
    this.router.transitionTo({
      queryParams: { showCatalog: undefined, ref: undefined },
    });
  }
}
