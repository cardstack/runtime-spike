import Component from '@glimmer/component';
import { getCardRefsForModule } from '../resources/card-refs';
import Schema from './schema';
import { Card } from '../lib/card-api';

interface Signature {
  Args: {
    url: string
    importModule: Record<string, typeof Card>;
  }
}

export default class Module extends Component<Signature> {
  <template>
    {{#each this.cardRefs.refs as |ref|}}
      <Schema @ref={{ref}} @module={{@importModule}} />
    {{/each}}
  </template>

  cardRefs = getCardRefsForModule(this, () => this.args.url);
}
