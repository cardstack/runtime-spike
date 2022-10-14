import Component from '@glimmer/component';
import type { ExportedCardRef } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
//@ts-ignore glint does not think `hash` is consumed-but it is in the template
import { hash } from '@ember/helper';
import Preview from './preview';
import { registerDestructor } from '@ember/destroyable';
import { service } from '@ember/service';
import type LocalRealm from '../services/local-realm';
import type LoaderService from '../services/loader-service';
import type RouterService from '@ember/routing/router-service';
import { taskFor } from 'ember-concurrency-ts';
import { enqueueTask } from 'ember-concurrency'
import type { Card } from 'https://cardstack.com/base/card-api';

export default class CreateCardModal extends Component {
  <template>
    {{#if this.cardRef}}
      <dialog class="dialog-box" open data-test-create-new-card={{this.cardRef.name}}>
        <button {{on "click" this.close}} type="button">X Close</button>
        <h1>Create New Card: {{this.cardRef.name}}</h1>
        {{#if this.card}}
          <Preview
            @card={{this.card}}
            @isNew={{true}}
            @realmURL={{this.localRealm.url.href}}
            @onSave={{this.save}}
            @onCancel={{this.close}}
          />
        {{/if}}
      </dialog>
    {{/if}}
  </template>

  @service declare localRealm: LocalRealm;
  @service declare loaderService: LoaderService;
  @service declare router: RouterService;

  @tracked card: Card | undefined;
  @tracked cardRef: ExportedCardRef | undefined;

  constructor(owner: unknown, args: {}) {
    super(owner, args);
    (globalThis as any)._CARDSTACK_CREATE_NEW_CARD = this;
    registerDestructor(this, () => {
      delete (globalThis as any)._CARDSTACK_CREATE_NEW_CARD;
    });
  }

  async create(ref: ExportedCardRef): Promise<void> {
    await taskFor(this._create).perform(ref);
  }

  @enqueueTask private async _create(ref: ExportedCardRef): Promise<void> {
    this.cardRef = ref;
    let module: Record<string, any> = await this.loaderService.loader.import(ref.module);
    let Clazz: typeof Card = module[ref.name];
    this.card = new Clazz();
  }

  @action save(path: string) {
    this.router.transitionTo({ queryParams: { path } });
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
