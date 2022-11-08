import { contains, field, Component, Card } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';

export class Treat extends Card {
  @field name = contains(StringCard);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div><@fields.name/></div>
    </template>
  }  
}