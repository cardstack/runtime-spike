import { contains, field, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import { Person } from './person';

export class FancyPerson extends Person {
  @field favoriteColor = contains(StringCard);
  static embedded = class Embedded extends Component<typeof this> {
    <template><@fields.firstName/> <@fields.lastName /> <@fields.favoriteColor/></template>
  }
  static isolated = class Isolated extends Component<typeof this> {
    <template><h1><@fields.firstName/> <@fields.lastName /></h1>
      <@fields.isCool/>
      <@fields.isHuman/>
      Color: <@fields.favoriteColor/>
    </template>
  }
}