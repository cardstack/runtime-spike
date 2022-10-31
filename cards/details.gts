import { contains, field, Card, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import TextAreaCard from 'https://cardstack.com/base/text-area';
import DateCard from 'https://cardstack.com/base/date';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let css =`
  this { display: flex; gap: 2rem; } 
  .label {
    color: #A0A0A0;
    font-size: 0.6875rem;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    line-height: 1.25;
  }
  .details {
    display: inline-grid;
    grid-template-columns: 1fr 1fr;
  }
  .memo {
    display: inline-grid;
    grid-template-columns: 1fr 2fr;
  }
`;

let styleSheet = initStyleSheet(css);

export class Details extends Card {
  @field invoiceNo = contains(StringCard);
  @field invoiceDate = contains(DateCard);
  @field dueDate = contains(DateCard);
  @field terms = contains(StringCard);
  @field invoiceDocument = contains(StringCard);
  @field memo = contains(TextAreaCard);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styleSheet}}>
        <div class="details">
          <div class="label">Invoice No.</div> <@fields.invoiceNo/>
          <div class="label">Invoice Date</div> <@fields.invoiceDate/>
          <div class="label">Due Date</div> <@fields.dueDate/>
          <div class="label">Terms</div> <@fields.terms/>
          <div class="label">Invoice Document</div> <@fields.invoiceDocument/>
        </div>
        <div class="memo">
          <div class="label">Memo</div> <@fields.memo/>
        </div>
      </div>
    </template>
  };
}