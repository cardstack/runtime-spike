import { contains, linksTo, containsMany, field, Card, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import { PaymentMethod } from './payment-method';
import { Vendor } from './vendor';

export class Payment extends Card {
  @field title = contains(StringCard);
  @field vendor = linksTo(Vendor);
  @field paymentMethods = containsMany(PaymentMethod);
  // @field primaryPayment = contains(PaymentMethod, { computeVia: function(this: Payment) { return this.paymentMethods.find(p => p.isPrimaryMethod); } });
  
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div>
        <@fields.title/>
        <@fields.paymentMethods/>
        {{!-- <@fields.primaryPayment/> --}}
        <@fields.vendor/>
      </div>
    </template>
  };
}