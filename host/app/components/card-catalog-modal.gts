import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { registerDestructor } from '@ember/destroyable';
import { taskFor } from 'ember-concurrency-ts';
import { enqueueTask } from 'ember-concurrency';
import type { Card } from 'https://cardstack.com/base/card-api';
import type { Query } from '@cardstack/runtime-common/query';
import { createNewCard, type ExportedCardRef } from '@cardstack/runtime-common';
import { Deferred } from '@cardstack/runtime-common/deferred';
import { getSearchResults, Search } from '../resources/search';
import Preview from './preview';

export default class CardCatalogModal extends Component {
  <template>
    {{#if this.currentRequest}}
      <dialog class="dialog-box card-catalog-dialog" open data-test-card-catalog-modal>
        <header class="dialog-box__header">
          <h1>Card Catalog</h1>
          <button {{on "click" (fn this.pick undefined)}} type="button">X Close</button>
        </header>
        <section class="dialog-box__content">
          {{#if this.currentRequest.search.isLoading}}
            Loading...
          {{else}}
            {{#if this.currentRequest.opts.offerToCreate}}
              <button {{on "click" (fn this.createNew this.currentRequest.opts.offerToCreate)}} data-test-create-new>Create New</button>
            {{/if}}
            <ul class="card-catalog" data-test-card-catalog>
              {{#each this.currentRequest.search.instances as |card|}}
                <li data-test-card-catalog-item={{card.id}}>
                  <Preview @card={{card}} @format="embedded" />
                  <button {{on "click" (fn this.pick card)}} type="button" data-test-select={{card.id}}>
                    Select
                  </button>
                </li>
              {{else}}
                <p>No cards available</p>
              {{/each}}
            </ul>
          {{/if}}
        </section>
      </dialog>
    {{/if}}
  </template>

  @tracked currentRequest: {
    search: Search;
    deferred: Deferred<Card | undefined>;
    opts?: { offerToCreate?: ExportedCardRef };
  } | undefined = undefined;

  constructor(owner: unknown, args: {}) {
    super(owner, args);
    (globalThis as any)._CARDSTACK_CARD_CHOOSER = this;
    registerDestructor(this, () => {
      delete (globalThis as any)._CARDSTACK_CARD_CHOOSER;
    });
  }

  async chooseCard<T extends Card>(query: Query, opts?: { offerToCreate: ExportedCardRef }): Promise<undefined | T> {
    return await taskFor(this._chooseCard).perform(query, opts) as T | undefined;
  }

  @enqueueTask private async _chooseCard<T extends Card>(query: Query, opts?: { offerToCreate: ExportedCardRef }): Promise<undefined | T> {
    this.currentRequest = {
      search: getSearchResults(this, () => query),
      deferred: new Deferred(),
      opts
    };
    let card = await this.currentRequest.deferred.promise;
    if (card) {
      return card as T;
    } else {
      return undefined;
    }
  }

  @action pick(card?: Card): void {
    if (this.currentRequest) {
      this.currentRequest.deferred.resolve(card);
      this.currentRequest = undefined;
    }
  }

  @action async createNew(ref: ExportedCardRef): Promise<void> {
    let newCard = await createNewCard(ref);
    this.pick(newCard);
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    CardCatalogModal: typeof CardCatalogModal;
   }
}
