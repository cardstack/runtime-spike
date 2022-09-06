import Component from '@glimmer/component';
import { service } from '@ember/service';
import { RealmPaths, Loader, type ExportedCardRef } from '@cardstack/runtime-common';
import type RouterService from '@ember/routing/router-service';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { action } from '@ember/object';
import { eq } from '../helpers/truth-helpers'
//@ts-ignore cached not available yet in definitely typed
import { cached } from '@glimmer/tracking';

import LocalRealm from '../services/local-realm';
import { directory, Entry } from '../resources/directory';

import CardCatalogModal from './card-catalog-modal';
import CreateNewCard from './create-new-card';

interface Args {
  Args: {
    // we want to use the local realm so that we can show a button
    // to open or close it.
    localRealm: LocalRealm;
    path: string | undefined;
  }
}

export default class FileTree extends Component<Args> {
  <template>
    {{#if @localRealm.isAvailable}}
      <button {{on "click" this.closeRealm}} type="button">Close local realm</button>
      {{#each this.listing.entries key="path" as |entry|}}
        {{#if (eq entry.kind 'file')}}
          <div class="item file {{if (eq entry.path @path) 'selected'}} indent-{{entry.indent}}"
            {{on "click" (fn this.open entry)}} role="button">
          {{entry.name}}
          </div>
        {{else}}
          <div class="item directory indent-{{entry.indent}}">
            {{entry.name}}
          </div>
        {{/if}}
      {{/each}}

      <button {{on "click" this.openCatalog}} type="button" data-test-create-new-card-button>
        Create New Card
      </button>
      <CardCatalogModal @onSelect={{this.selectFromCatalog}} />
      {{#if this.selectedRef}}
        <CreateNewCard
          @cardRef={{this.selectedRef}}
          @realmURL={{@localRealm.url.href}}
          @onClose={{this.onCloseCreateNewCard}}
        />
      {{/if}}

    {{else if @localRealm.isLoading }}
      ...
    {{else if @localRealm.isEmpty}}
      <button {{on "click" this.openRealm}} type="button">Open a local realm</button>
    {{/if}}
  </template>

  listing = directory(this, () => this.args.localRealm.isAvailable ? "http://local-realm/" : undefined)
  @service declare router: RouterService;
  @tracked selectedRef: ExportedCardRef | undefined;

  @cached
  get realmPath() {
    if (!this.args.localRealm.isAvailable) {
      throw new Error('Realm is not available');
    }
    return new RealmPaths(Loader.reverseResolution(this.args.localRealm.url.href));
  }

  @action
  openRealm() {
    this.args.localRealm.chooseDirectory(() => this.router.refresh());
  }

  @action
  closeRealm() {
    if (this.args.localRealm.isAvailable) {
      this.args.localRealm.close();
      this.router.transitionTo({ queryParams: { path: undefined, showCatalog: undefined } });
    }
  }

  @action
  open(entry: Entry) {
    let { path } = entry;
    this.router.transitionTo({ queryParams: { path, showCatalog: undefined } });
  }

  @action
  openCatalog() {
    this.router.transitionTo({ queryParams: { showCatalog: true } });
  }

  @action
  selectFromCatalog(ref: ExportedCardRef) {
    this.selectedRef = ref;
  }

  @action
  onCloseCreateNewCard() {
    this.selectedRef = undefined;
  }
}
