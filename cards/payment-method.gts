import { contains, field, Card, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import BooleanCard from 'https://cardstack.com/base/boolean';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let css =`this { margin-top: 1.25rem; } .currency { font-weight: bold; font-size: 1rem; } .value { color: #5A586A; }`;

let styleSheet = initStyleSheet(css);

export class PaymentMethod extends Card {
  @field currencyName = contains(StringCard);
  @field value = contains(StringCard);
  @field isPrimaryMethod = contains(BooleanCard);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <div class="currency"><@fields.currencyName/></div>
        <div class="value"><@fields.value/></div>
      </div>
    </template>
  };
}