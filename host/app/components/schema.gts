
import Component from '@glimmer/component';
import { CardRef } from '@cardstack/runtime-common';
import { getCardType } from '../resources/card-type';

interface Signature {
  Args: {
    ref: CardRef
  }
}

export default class Schema extends Component<Signature> {
  <template>
    {{#if this.cardType.type}}
      <p>
        <div>Card ID: {{this.cardType.type.id}}</div>
        <div>Adopts From: {{this.cardType.type.super.id}}</div>
        <div>Fields:</div>
        <ul>
          {{#each this.cardType.type.fields as |field|}}
            <li>{{field.name}} - {{field.type}} - field card ID: {{field.card.id}}</li>
          {{/each}}
        </ul>
      </p>
    {{/if}}
  </template>

  cardType = getCardType(this, () => this.args.ref);
}