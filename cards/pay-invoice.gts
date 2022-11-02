import { contains, linksTo, field, Card, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import { Vendor } from './vendor';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let css =`this { background-color: white; border: 1px solid gray; border-radius: 10px; padding: 1rem; }`;
let styleSheet = initStyleSheet(css);

export class PayInvoice extends Card {
  @field title = contains(StringCard);
  @field vendor = linksTo(Vendor);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <h3><@fields.title/></h3>
        <@fields.vendor/>
      </div>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <h1><@fields.title/></h1>
        <section>
          <h2>Vendor</h2>
          <@fields.vendor/>
        </section>
      </div>
    </template>
  };
}