import { contains, linksTo, field, Component, Card } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import TextAreaCard from 'https://cardstack.com/base/text-area';
import { BlogPerson as Person } from './blog/blog-person';
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let imageURL = new URL('./logo.png', import.meta.url).href;

let styles = initStyleSheet(`this { background-color: #ffcad4; border: 1px solid gray; border-radius: 10px; padding: 1rem; }`);

export class BasicCard extends Card {
  @field title = contains(StringCard);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      Title: <@fields.title/>
    </template>
  }
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      Title: <@fields.title/>
    </template>
  }
}

export class VeryBasicCard extends BasicCard {
  @field description = contains(StringCard);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      Title: <@fields.title/>
      Description: <@fields.description/>
    </template>
  }
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      Title: <@fields.title/>
      Description: <@fields.description/>
    </template>
  }
}

export class Post extends Card {
  @field author = contains(Person);
  @field title = contains(StringCard);
  @field body = contains(TextAreaCard);
  @field titleRef = contains(VeryBasicCard);
  @field linkedRef = linksTo(VeryBasicCard);
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div {{attachStyles styles}}>
        <h1><@fields.title/><img src="{{imageURL}}"></h1>
        <h3>by <@fields.author.firstName/> <@fields.author.lastName/></h3>
        <p><@fields.body/></p>
        <p><@fields.titleRef/></p>
      </div>
    </template>
  }
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styles}}>
        <em><@fields.title/></em> by <@fields.author.firstName/> <@fields.author.lastName/>
        <p><@fields.titleRef/></p>
      </div>
    </template>
  }
}
