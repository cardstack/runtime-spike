import Component from '@glimmer/component';
import { type ExportedCardRef, LooseCardDocument } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
//@ts-ignore glint does not think `hash` is consumed-but it is in the template
import { hash } from '@ember/helper';
import Preview from './preview';
import { registerDestructor } from '@ember/destroyable';
import { taskFor } from 'ember-concurrency-ts';
import { enqueueTask } from 'ember-concurrency';
import { service } from '@ember/service';
import type LocalRealm from '../services/local-realm';
import type LoaderService from '../services/loader-service';
import type { Card } from 'https://cardstack.com/base/card-api';

export default class CreateCardModal extends Component {
  <template>
    {{#if this.cardRef}}
      <dialog class="dialog-box" open data-test-create-new-card={{this.cardRef.name}}>
        <button {{on "click" this.close}} type="button">X Close</button>
        <h1>Create New Card: {{this.cardRef.name}}</h1>
        <Preview
          @card={{hash type="new" realmURL=this.localRealm.url.href cardSource=this.cardRef}}
          @onSave={{this.save}}
          @onCancel={{this.close}}
        />
      </dialog>
    {{/if}}
  </template>

  @service declare localRealm: LocalRealm;
  @service declare loaderService: LoaderService;

  @tracked cardRef: ExportedCardRef | undefined;

  constructor(owner: unknown, args: {}) {
    super(owner, args);
    (globalThis as any)._CARDSTACK_CREATE_NEW_CARD = this;
    registerDestructor(this, () => {
      delete (globalThis as any)._CARDSTACK_CREATE_NEW_CARD;
    });
  }

  async create<T extends Card>(ref: ExportedCardRef): Promise<undefined | T> {
    return await taskFor(this._create).perform(ref) as T | undefined;
  }

  @enqueueTask private async _create<T extends Card>(ref: ExportedCardRef): Promise<undefined | T> {
    this.cardRef = ref;
    // TODO: create card or retrieve newly created card?

    // if (resource) {
    //   let api = await this.loaderService.loader.import<typeof import('https://cardstack.com/base/card-api')>('https://cardstack.com/base/card-api');
    //   return await api.createFromSerialized(resource, this.localRealm.url, { loader: this.loaderService.loader }) as T;
    // } else {
      return undefined;
    // }
  }

  @action save(path: string, data: LooseCardDocument) {
    console.log(path, data);
    // TODO
    this.close();
  }

  @action close(): void {
    this.cardRef = undefined;
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    CreateCardModal: typeof CreateCardModal;
   }
}
