import Component from '@glimmer/component';
import { RealmPaths, Loader, catalogEntryRef, type ExportedCardRef } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { LinkTo } from '@ember/routing';
import { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';
//@ts-ignore cached not available yet in definitely typed
import { cached } from '@glimmer/tracking';
//@ts-ignore glint does not think this is consumed-but it is consumed in the template
import { hash } from '@ember/helper';
import { fn } from '@ember/helper';
import qs from 'qs';

import { getSearchResults } from '../resources/search';
import LocalRealm from '../services/local-realm';
import ModalService from '../services/modal';
import CardEditor from './card-editor';

interface Signature {
  Args: {
    ref: ExportedCardRef;
  }
}

export default class CatalogEntryEditor extends Component<Signature> {
  <template>
    <div class="catalog-entry-editor" data-test-catalog-entry-editor>
      {{#if this.entry}}
        <fieldset>
          <legend>Edit Catalog Entry</legend>
          <LinkTo @route="application" @query={{hash path=(this.modulePath (ensureJsonExtension this.entry.id))}} data-test-catalog-entry-id>
            {{this.entry.id}}
          </LinkTo>
          <CardEditor
            @moduleURL={{this.entry.meta.adoptsFrom.module}}
            @cardArgs={{hash type="existing" url=this.entry.id format="edit"}}
          />
          <button {{on "click" (fn this.openCatalog this.entry.attributes.ref)}} type="button">
            Open Catalog
          </button>
        </fieldset>
      {{else}}
        {{#if this.showEditor}}
          <fieldset>
            <legend>Publish New Card Type</legend>
            <CardEditor
              @moduleURL={{this.catalogEntryRef.module}}
              @cardArgs={{hash type="new" realmURL=this.localRealm.url.href cardSource=this.catalogEntryRef initialAttributes=this.catalogEntryAttributes}}
              @onSave={{this.onSave}}
              @onCancel={{this.onCancel}}
            />
          </fieldset>
        {{else}}
          <button {{on "click" this.displayEditor}} type="button" data-test-catalog-entry-publish>
            Publish Card Type
          </button>
        {{/if}}
      {{/if}}
    </div>
  </template>

  @service declare localRealm: LocalRealm;
  @service declare router: RouterService;
  @service declare modal: ModalService;
  catalogEntryRef = catalogEntryRef;
  catalogEntryAttributes = {
    title: this.args.ref.name,
    description: `Catalog entry for ${this.args.ref.name} card`,
    ref: this.args.ref,
  }
  catalogEntry = getSearchResults(this, () => ({
    filter: {
      on: this.catalogEntryRef,
      eq: { ref: this.args.ref },
    },
  }));
  @tracked showEditor = false;

  @cached
  get realmPath() {
    if (!this.localRealm.isAvailable) {
      throw new Error('Local realm is not available');
    }
    return new RealmPaths(Loader.reverseResolution(this.localRealm.url.href));
  }

  get entry() {
    return this.catalogEntry.instances[0];
  }

  @action
  modulePath(url: string): string {
    return this.realmPath.local(new URL(url));
  }

  @action
  displayEditor() {
    this.showEditor = true;
  }

  @action
  onCancel() {
    this.showEditor = false;
  }

  @action
  onSave(url: string) {
    let path = this.realmPath.local(new URL(url));
    this.router.transitionTo({ queryParams: { path } });
  }

  @action
  openCatalog(ref: ExportedCardRef) {
    this.router.transitionTo({ queryParams: { showCatalog: true, ref: qs.stringify(ref) }});
  }
}

function ensureJsonExtension(url: string) {
  if (!url.endsWith('.json')) {
    return `${url}.json`;
  }
  return url;
}
