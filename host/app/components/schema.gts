import Component from '@glimmer/component';
import { CardRef } from '@cardstack/runtime-common';
import { getCardType } from '../resources/card-type';
import { action } from '@ember/object';
import { service } from '@ember/service';
import LocalRealm from '../services/local-realm';
import { RealmPaths } from '@cardstack/runtime-common/paths';
//@ts-ignore cached not available yet in definitely typed
import { cached } from '@glimmer/tracking';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { LinkTo } from '@ember/routing';
//@ts-ignore glint does not think this is consumed-but it is consumed in the template
import { hash } from '@ember/helper';
import CardEditor from './card-editor';
import { Card } from '../lib/card-api';
import { NewCardArgs } from './card-editor';
import type RouterService from '@ember/routing/router-service';

interface Signature {
  Args: {
    ref: CardRef;
    module: Record<string, typeof Card>;
  }
}

export default class Schema extends Component<Signature> {
  <template>
    {{#if this.cardType.type}}
      {{#if this.showEditor}}
        <CardEditor
          @card={{this.cardArgs}}
          @module={{@module}}
          @onSave={{this.onSave}}
          @onCancel={{this.onCancel}}
        />
      {{else}}
        <p>
          <div data-test-card-id>Card ID: {{this.cardType.type.id}}</div>
          <div data-test-adopts-from>Adopts From: {{this.cardType.type.super.id}}</div>
          <div>Fields:</div>
          <ul>
            {{#each this.cardType.type.fields as |field|}}
              <li data-test-field={{field.name}}>{{field.name}} - {{field.type}} - field card ID:
                {{#if (this.inRealm field.card.exportedCardContext.module)}}
                  <LinkTo
                    @route="application"
                    @query={{hash path=(this.modulePath field.card.exportedCardContext.module)}}
                  >
                    {{field.card.id}}
                  </LinkTo>
                {{else}}
                  {{field.card.id}}
                {{/if}}
              </li>
            {{/each}}
          </ul>
        </p>
        <button {{on "click" this.displayEditor}} data-test-create-card>Create New {{this.cardType.type.exportedCardContext.name}}</button>
      {{/if}}
    {{/if}}
  </template>

  @service declare localRealm: LocalRealm;
  @service declare router: RouterService;
  @tracked showEditor = false;

  @cached
  get realmPath() {
    if (!this.localRealm.isAvailable) {
      throw new Error('Local realm is not available');
    }
    return new RealmPaths(this.localRealm.url);
  }

  get cardType() {
    return getCardType(this, () => this.args.ref);
  }

  get cardArgs(): NewCardArgs {
    if (!this.cardType.type) {
      throw new Error('can not instantiate internal card type');
    }

    return {
      type: 'new',
      class: this.args.module[this.cardType.type.exportedCardContext.name],
      name: this.cardType.type.exportedCardContext.name,
    }
  }

  @action
  inRealm(url: string): boolean {
    return this.realmPath.inRealm(new URL(url));
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
    let path = new URL(url).pathname;
    this.router.transitionTo({ queryParams: { path } });
  }
}
