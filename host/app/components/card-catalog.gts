import Component from '@glimmer/component';
import { type CardResource, catalogEntryRef } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '../helpers/truth-helpers'
//@ts-ignore glint does not think this is consumed-but it is consumed in the template
import { hash } from '@ember/helper';

import { getSearchResults } from '../resources/search';
import CardEditor from './card-editor';

interface Signature {
  Args: {
    realmURL: string;
    onSelect?: (entry: CardResource | undefined) => void;
  }
}

export default class CardCatalog extends Component<Signature> {
  <template>
    <div data-test-card-catalog>
      {{#if (eq this.state "loading")}}
        Loading...
      {{else if (eq this.state "loaded")}}
        <ul class="card-catalog">
          {{#each this.entries as |entry|}}
            <li data-test-card-catalog-item={{entry.id}}>
              <CardEditor
                @moduleURL={{entry.meta.adoptsFrom.module}}
                @cardArgs={{hash type="existing" url=entry.id format="embedded"}}
              />
              {{#if @onSelect}}
                <button {{on "click" (fn @onSelect entry)}} type="button" data-test-select={{entry.id}}>
                  Select
                </button>
              {{/if}}
            </li>
          {{/each}}
        </ul>
      {{else}}
        No cards available
      {{/if}}
    </div>
  </template>

  catalogEntry = getSearchResults(this,
    () => ({ filter: { type: catalogEntryRef }}),
    () => this.args.realmURL,
  );

  get entries() {
    return this.catalogEntry.instances;
  }

  get state() {
    if (this.catalogEntry.isLoading) {
      return 'loading';
    } else if (this.entries.length > 0) {
      return 'loaded';
    } else {
      return 'empty';
    }
  }
}
