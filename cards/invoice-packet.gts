import { contains, containsMany, linksTo, field, Card, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import IntegerCard from 'https://cardstack.com/base/integer';
import TextAreaCard from 'https://cardstack.com/base/text-area';
import DateCard from 'https://cardstack.com/base/date';
import { Vendor } from './vendor';
import { PaymentMethod } from './payment-method';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let invoiceStyles = initStyleSheet(`
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
    max-width: 50rem;
    background-color: #fff; 
    border: 1px solid gray; 
    border-radius: 10px; 
    font-family: "Open Sans", Helvetica, Arial, sans-serif;
    font-size: 0.8125rem;
    letter-spacing: 0.01em;
    line-height: 1.25;
    overflow: hidden;
  }
  .header {
    padding: 2rem;
    background-color: #F8F7FA;
  }
  .invoice {
    padding: 2rem;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 3rem 0;
  }
  h1 {
    margin: 0;
    font-size: 1.275rem;
    letter-spacing: 0.015em;
    line-height: 1.875;
  }
  .label {
    margin-bottom: 1rem;
    color: #A0A0A0;
    font-size: 0.6875rem;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    line-height: 1.25;
  }
  .details {
    display: grid;
    grid-template-columns: 1fr 2fr;
    gap: 0 1rem;
  }

  .line-items {
    grid-column: 1 / -1;
  }
  .line-items__header {
    display: grid;
    grid-template-columns: 3fr 1fr 2fr; 
  }
  .line-items__header > *:last-child {
    justify-self: end;
  }
  .line-items__rows {
    padding: 2rem 0;
    border-top: 1px solid #E8E8E8;
    border-bottom: 1px solid #E8E8E8;
  }
  .line-items__rows > * + * {
    margin-top: 1.25rem;
  }

  .payment-methods {
    display: grid;
    grid-template-columns: 1fr 1fr;
  }
  .payment-method + .payment-method {
    margin-top: 1rem;
  }
  .payment-method__currency { 
    font-weight: bold; 
    font-size: 1rem; 
  } 
  .payment-method__amount { 
    color: #5A586A; 
  }

  .balance-due {
    text-align: right;
  }
  .balance-due__total {
    font-size: 1.625rem;
    font-weight: bold;
  }
`);

let lineItemStyles = initStyleSheet(`
  this {
    display: grid;
    grid-template-columns: 3fr 1fr 2fr; 
  }
  .line-item__amount {
    justify-self: end;
  }
`)

class LineItem extends Card {
  @field name = contains(StringCard);
  @field quantity = contains(IntegerCard);
  @field amount = contains(IntegerCard);
  @field description = contains(StringCard);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles lineItemStyles}}>
        <div>
          <div><strong><@fields.name/></strong></div>
          <@fields.description/>
        </div>
        <div><@fields.quantity/></div>
        <div class="line-item__amount">
          <strong>{{formatUSD @model.amount}}</strong>
        </div>
      </div>
    </template>
  };
}

function balanceInCurrency (balance: number, exchangeRate: number, currency: string) {
  if (balance == null || exchangeRate == null) {
    return 0;
  }
  let total = balance * exchangeRate;
  if (currency === 'USD') {
    return formatUSD(total);
  } else {
    return `${Number.isInteger(total) ? total : total.toFixed(2)} ${currency}`;
  }
}

function formatUSD(amount: number) {
  return `$ ${amount.toFixed(2)} USD`;
}

class InvoiceTemplate extends Component<typeof InvoicePacket> {
  <template>
    <div {{attachStyles invoiceStyles}}>
      <header class="header">
        <h1>Invoice</h1>
      </header>
      <section class="invoice">
        <section class="vendor">
          <div class="label">Vendor</div> <@fields.vendor/>
        </section>
        <section class="details">
          <div class="label">Invoice No.</div><div><@fields.invoiceNo/></div>
          <div class="label">Invoice Date</div><div><@fields.invoiceDate/></div>
          <div class="label">Due Date</div><div><@fields.dueDate/></div>
          <div class="label">Terms</div> <div><@fields.terms/></div>
          <div class="label">Invoice Document</div> <div><@fields.invoiceDocument/></div>
          <div class="label">Memo</div> <div><@fields.memo/></div>
        </section>
        <section class="line-items">
          <header class="line-items__header">
            <div class="label">Goods / services rendered</div>
            <div class="label">Qty</div>
            <div class="label">Amount</div>
          </header>
          <div class="line-items__rows">
            <@fields.lineItems />
          </div>
        </section>
        <section class="payment-methods">
          <div>
            <div class="label">Primary<br> Payment Method</div>
            {{#let @model.primaryPayment as |payment|}}
              {{#if payment.currency}}
                <div class="payment-method">
                  <div class="payment-method__currency">{{payment.logo}} {{payment.currency}}</div>
                  <div class="payment-method__amount">
                    {{balanceInCurrency @model.balanceDue payment.exchangeRate payment.currency}}
                  </div>
                </div>
              {{/if}}
            {{/let}}
          </div>
          <div>
            <div class="label">Alternate<br> Payment Methods</div>
            {{#each @model.alternatePayments as |payment|}}
              {{#if payment.currency}}
                <div class="payment-method">
                  <div class="payment-method__currency">{{payment.logo}} {{payment.currency}}</div>
                  <div class="payment-method__amount">
                    {{balanceInCurrency @model.balanceDue payment.exchangeRate payment.currency}}
                  </div>
                </div>
              {{/if}}
            {{/each}}
          </div>
        </section>
        <section class="balance-due">
          <div class="label">Balance Due</div>
          <div class="balance-due__total">{{formatUSD @model.balanceDue}}</div>
        </section>
      </section>
    </div>
  </template>
}

export class InvoicePacket extends Card {
  @field vendor = linksTo(Vendor);
  @field invoiceNo = contains(StringCard);
  @field invoiceDate = contains(DateCard);
  @field dueDate = contains(DateCard);
  @field terms = contains(StringCard);
  @field invoiceDocument = contains(StringCard);
  @field memo = contains(TextAreaCard);
  @field lineItems = containsMany(LineItem);
  @field primaryPayment = contains(PaymentMethod);
  @field alternatePayments = containsMany(PaymentMethod);
  @field balanceDue = contains(IntegerCard, { computeVia: 
    function(this: InvoicePacket) { 
      return this.lineItems.length === 0 ? 0 : this.lineItems.map(i => i.amount * i.quantity).reduce((a, b) => (a + b)); 
    }
  });

  static embedded = InvoiceTemplate;
  static isolated = InvoiceTemplate;
}