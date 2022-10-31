import { contains, field, Card, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import IntegerCard from 'https://cardstack.com/base/integer';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let css =`this { display: flex; gap: 2rem; }`;

let styleSheet = initStyleSheet(css);

export class LineItem extends Card {
  @field name = contains(StringCard);
  @field quantity = contains(IntegerCard);
  @field amount = contains(IntegerCard);
  @field description = contains(StringCard);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <div>
          <strong><@fields.name/></strong>
          <p><@fields.description/></p>
        </div>
        <@fields.quantity/>
        <strong><@fields.amount/></strong>
      </div>
    </template>
  };
}