import { contains, containsMany, field, Card, Component } from 'https://cardstack.com/base/card-api';
import IntegerCard from 'https://cardstack.com/base/integer';
import { Vendor } from './vendor';
import { Details } from './details';
import { LineItem } from './line-item';
import { PaymentMethod } from './payment-method';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let css =`
  @font-face {
    font-family: "Open Sans";
    src: url("./fonts/OpenSans-Regular.ttf");
    font-weight: 400;
  }
  @font-face {
    font-family: "Open Sans";
    src: url("./fonts/OpenSans-Bold.ttf");
    font-weight: 700;
  }
  this { 
    font-family: "Open Sans", Helvetica, Arial, sans-serif;
    font-size: 0.8125rem;
    letter-spacing: 0.01em;
    line-height: 1.25;
    background-color: #fff; border: 1px solid gray; border-radius: 10px; padding: 1rem; 
  }
  h1 {
    font-size: 1.275rem;
    letter-spacing: 0.015em;
    line-height: 1.875;
  }
  h2 {
    font-size: 1rem;
    letter-spacing: 0;
    line-height: 1.275;
    margin-top: 0;
    margin-bottom: 1.25rem;
  }
  section + section {
    margin-top: 2rem;
  }
  .label {
    color: #A0A0A0;
    font-size: 0.6875rem;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    line-height: 1.25;
  }
  .line-items__header {
    display: flex;
    justify-content: space-between;
    border-bottom: 1px solid #E8E8E8;
  }
  .line-items__list {
    padding: 2rem 0;
    border-bottom: 1px solid #E8E8E8;
    list-style: none;
  }
  .line-items__row {
    display: flex;
    justify-content: space-between;
  }
  .line-items__row + .line-items__row {
    margin-top: 1.25rem;
  }
  .payment,
  .payment-methods {
    display: flex;
    justify-content: space-between;
    gap: 2rem;
  }
  .total-balance {
    font-size: 1.625rem;
    font-weight: bold;
  }
  .balance-due {
    text-align: right;
  }
  `;

let styleSheet = initStyleSheet(css);

export class InvoicePacket extends Card {
  @field vendor = contains(Vendor);
  @field details = contains(Details);
  @field lineItems = containsMany(LineItem);
  @field paymentMethods = containsMany(PaymentMethod);
  @field primaryPayment = contains(PaymentMethod, { computeVia: function(this: InvoicePacket) { return this.paymentMethods.find(p => p.isPrimaryMethod); } });
  @field alternatePayments = containsMany(PaymentMethod, { computeVia: function(this: InvoicePacket) { return this.paymentMethods.filter(p => !p.isPrimaryMethod); } });
  @field balanceDue = contains(IntegerCard, { computeVia: function(this: InvoicePacket) { return this.lineItems.length === 0 ? 0 : this.lineItems.map(i => i.amount).reduce((a, b) => (a + b)); } });
  
  
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <@fields.vendor/>
        <@fields.details/>
        <@fields.lineItems/>
        <@fields.primaryPayment/>
      </div>
    </template>
  };

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <header>
          <h1>Invoice</h1>
        </header>
        <section>
          <h2>Vendor</h2>
          <@fields.vendor/>
        </section>
        <section>
          <h2>Details</h2>
          <@fields.details/>
        </section>

        <section>
          <h2>Line Items</h2>
          <header class="line-items__header">
            <div class="label">Goods / services rendered</div>
            <div class="label">Qty</div>
            <div class="label">Amount</div>
          </header>
          <ul class="line-items__list">
            {{#each @model.lineItems as |item|}}
              <li class="line-items__row">
                <div>
                  <div><strong>{{item.name}}</strong></div>
                  {{item.description}}
                </div>
                <div>{{item.quantity}}</div>
                <div><strong>{{item.amount}}</strong></div>
              </li>
            {{/each}}
          </ul>
        </section>

        <section class="payment">
          <div>
            <h2>Payment Methods</h2>
            <div class="payment-methods">
              <div>
                <div class="label">Primary<br> Payment Method</div>
                <@fields.primaryPayment/>
              </div>
              <div>
                <div class="label">Alternate<br> Payment Methods</div>
                <@fields.alternatePayments/>
              </div>
            </div>
          </div>
          <div class="balance-due">
            <div class="label">Balance Due</div>
            <div class="total-balance">$ <@fields.balanceDue/> USD</div>
          </div>
        </section>
      </div>
    </template>
  };
}