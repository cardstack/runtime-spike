import Component from '@glimmer/component';
import type { ExportedCardRef } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { eq } from '../helpers/truth-helpers'
import { service } from '@ember/service';
//@ts-ignore glint does not think this is consumed-but it is consumed in the template
import { hash } from '@ember/helper';
import ModalService from '../services/modal';
import CardEditor from './card-editor';

interface Signature {
  Args: {
    onSelect?: (entry: ExportedCardRef) => void;
  }
}

export default class CardCatalogModal extends Component<Signature> {
  <template>
    <dialog class="dialog-box" open={{this.modal.isShowing}} data-test-card-modal>
      <button {{on "click" this.closeCatalog}} type="button">X Close</button>
      <h1>Card Catalog</h1>
      <div>
        {{#let this.modal.state as |state|}}
          {{#if (eq state.name "loading")}}
            Loading...
          {{else if (eq state.name "loaded")}}
            <ul class="card-catalog">
              {{#each state.entries as |entry|}}
                <li data-test-card-catalog-item={{entry.id}}>
                  <CardEditor
                    @moduleURL={{entry.meta.adoptsFrom.module}}
                    @cardArgs={{hash type="existing" url=entry.id format="embedded"}}
                  />
                  <button {{on "click" (fn this.select entry.attributes.ref)}} type="button" data-test-select={{entry.id}}>
                    Select
                  </button>
                </li>
              {{/each}}
            </ul>
          {{else}}
            <p>No cards available</p>
          {{/if}}
        {{/let}}
      </div>
    </dialog>
  </template>

  @service declare modal: ModalService;

  @action
  select(ref: ExportedCardRef) {
    this.args.onSelect?.(ref);
    this.closeCatalog();
  }

  @action
  closeCatalog() {
    this.modal.close();
  }
}
