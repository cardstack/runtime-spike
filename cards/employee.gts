import { contains, field, Component } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import { Person } from './person';

export class Employee extends Person {
  @field department = contains(StringCard);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <@fields.firstName/> from <em><@fields.department/></em>
    </template>
  }
  static isolated = class Isolated extends Component<typeof this> {
    <template><h1><@fields.firstName/> <@fields.lastName /></h1>
      <div><@fields.isCool/></div>
      <div><@fields.isHuman/></div>
      <div>Department: <@fields.department/></div>
    </template>
  }
}