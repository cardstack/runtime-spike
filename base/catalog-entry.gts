import { contains, field, Component, Card, primitive } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import BooleanCard from 'https://cardstack.com/base/boolean';
import CardRefCard from 'https://cardstack.com/base/card-ref';
import { Loader } from "@cardstack/runtime-common";

export class CatalogEntry extends Card {
  @field title = contains(StringCard);
  @field description = contains(StringCard);
  @field ref = contains(CardRefCard);
  @field isPrimitive = contains(BooleanCard, { computeVia: async function(this: CatalogEntry) {
    let module: Record<string, any> = await Loader.import(this.ref.module);
    let Clazz: typeof Card = module[this.ref.name];
    return primitive in Clazz;
  }});
  @field demo = contains(Card);

  // An explicit edit template is provided since computed isPrimitive bool
  // field (which renders in the embedded format) looks a little wonky
  // right now in the edit view.
  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class="card-edit">
        <label data-test-field="title">Title
          <@fields.title/>
        </label>
        <label data-test-field="description">Description
          <@fields.description/>
        </label>
        <div data-test-field="ref">Ref
          <@fields.ref/>
        </div>
        <div data-test-field="demo">Demo
          <@fields.demo/>
        </div>
      </div>
    </template>
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <h3><@fields.title/></h3>
      <p><em><@fields.description/></em></p>
      <div class="card"><@fields.demo/></div>
    </template>
  }
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <h1 data-test-title><@fields.title/></h1>
      <p data-test-description><em><@fields.description/></em></p>
      <div data-test-ref><@fields.ref/></div>
      <div><@fields.isPrimitive/></div>
      <div class="card" data-test-demo><@fields.demo/></div>
    </template>
  }
}