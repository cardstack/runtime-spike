import { contains, linksTo, field, Component, Card } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import BooleanCard from 'https://cardstack.com/base/boolean';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';
import { Pet } from './pet';

let styles = initStyleSheet(`this { background-color: #90dbf4; border: 1px solid gray; border-radius: 10px; padding: 1rem; }`);

export class Person extends Card {
  @field firstName = contains(StringCard);
  @field lastName = contains(StringCard);
  @field isCool = contains(BooleanCard);
  @field isHuman = contains(BooleanCard);
  @field pet = linksTo(Pet);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styles}}>
        <h3><@fields.firstName/> <@fields.lastName/></h3>
        <div>Pet: <@fields.pet/></div>
      </div>
    </template>
  }
  
  static isolated = class Isolated extends Component<typeof Person> {
    <template>
      <div {{attachStyles styles}}>
        <h1><@fields.firstName/> <@fields.lastName /></h1>
        <div><@fields.isCool/></div>
        <div><@fields.isHuman/></div>
        <div><@fields.pet/></div>
      </div>
    </template>
  }  
}