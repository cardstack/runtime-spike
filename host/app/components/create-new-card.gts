import Component from '@glimmer/component';
import type { ExportedCardRef } from '@cardstack/runtime-common';
import { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
//@ts-ignore glint does not think `hash` is consumed-but it is in the template
import { hash } from '@ember/helper';
import CardEditor from './card-editor';

interface Signature {
  Args: {
    cardRef: ExportedCardRef;
    realmURL: string;
    onClose: () => void;
  }
}

export default class CreateNewCard extends Component<Signature> {
  <template>
    {{#if @cardRef}}
      <dialog class="dialog-box" open>
        <button {{on "click" @onClose}} type="button">X Close</button>
        <div data-test-create-new={{@cardRef.name}}>
          <h1>Create New Card: {{@cardRef.name}}</h1>
          <CardEditor
            @moduleURL={{@cardRef.module}}
            @cardArgs={{hash type="new" realmURL=@realmURL cardSource=@cardRef}}
            @onSave={{this.save}}
            @onCancel={{@onClose}}
          />
        </div>
      </dialog>
    {{/if}}
  </template>

  @service declare router: RouterService;

  @action
  save(path: string) {
    this.router.transitionTo({ queryParams: { path } });
    this.args.onClose();
  }
}
