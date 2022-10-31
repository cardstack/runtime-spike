import { contains, field, Card, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import IntegerCard from 'https://cardstack.com/base/integer';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let css =`this { display: flex; gap: 2rem; }`;

let styleSheet = initStyleSheet(css);

export class Vendor extends Card {
  @field vendorName = contains(StringCard);
  @field addressLine = contains(StringCard);
  @field city = contains(StringCard);
  @field state = contains(StringCard);
  @field zipCode = contains(IntegerCard);
  @field email = contains(StringCard);
  @field logo = contains(StringCard);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <div>
          <div><@fields.vendorName/></div>
          <div><@fields.addressLine/></div>
          <div><@fields.city/>, <@fields.state/> <@fields.zipCode/></div>
          <div><@fields.email/></div>
        </div>
        <@fields.logo/>
      </div>
    </template>
  };
}