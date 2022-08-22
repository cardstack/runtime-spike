import Component from '@glimmer/component';
import { getSearchResults } from '../resources/search';
import type { ExportedCardRef } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import ImportedModuleEditor from './imported-module-editor';
import { LinkTo } from '@ember/routing';
import { service } from '@ember/service';
import LocalRealm from '../services/local-realm';
import type RouterService from '@ember/routing/router-service';
import { RealmPaths } from '@cardstack/runtime-common/paths';
import { Loader } from '@cardstack/runtime-common/loader';
//@ts-ignore cached not available yet in definitely typed
import { tracked, cached } from '@glimmer/tracking';
//@ts-ignore glint does not think this is consumed-but it is consumed in the template
import { hash } from '@ember/helper';

interface Signature {
  Args: {
    ref: ExportedCardRef;
  }
}

export default class CardCatalog extends Component<Signature> {
  <template>
    <ul>
      {{#if this.entry}}
        <li>
          <LinkTo @route="application" @query={{hash path=(this.modulePath (ensureJsonExtension this.entry.id))}}>
            {{this.entry.id}}
          </LinkTo>
          <fieldset>
            <legend>Catalog Entry Editor</legend>
            <ImportedModuleEditor
              @moduleURL={{this.entry.meta.adoptsFrom.module}}
              @cardArgs={{hash type="existing" url=this.entry.id json=(hash data=this.entry) format="edit"}}
              @onSave={{this.onSave}}
            />
          </fieldset>
          {{!-- TODO: Catalog Entry Preview --}}
        </li>
      {{else}}
        {{#if this.showEditor}}
          <fieldset>
            <legend>Publish New Card Type</legend>
            <ImportedModuleEditor
              @moduleURL={{this.catalogEntryRef.module}}
              @cardArgs={{hash type="new" realmURL=this.localRealm.url.href cardSource=this.catalogEntryRef initialAttributes=this.catalogEntryAttributes}}
              @onSave={{this.onSave}}
              @onCancel={{this.onCancel}}
            />
          </fieldset>
        {{else}}
          <button {{on "click" this.displayEditor}} type="button">
            Publish Card Type
          </button>
        {{/if}}
      {{/if}}
    </ul>
  </template>

  @service declare localRealm: LocalRealm;
  @service declare router: RouterService;
  catalogEntryRef: ExportedCardRef = {
    module: 'https://cardstack.com/base/catalog-entry',
    name: 'CatalogEntry',
  };
  catalogEntryAttributes = {
    title: this.args.ref.name,
    description: `Catalog entry for ${this.args.ref.name} type`,
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
}

function ensureJsonExtension(url: string) {
  if (!url.endsWith('.json')) {
    return `${url}.json`;
  }
  return url;
}
