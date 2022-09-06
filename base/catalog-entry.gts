import { contains, field, Component, Card, primitive } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import BooleanCard from 'https://cardstack.com/base/boolean';
import CardRefCard from 'https://cardstack.com/base/card-ref';
import { Loader, openCatalog } from "@cardstack/runtime-common";
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

class EditView extends Component<typeof CatalogEntry> {
  <template>
    <div class="card-edit">
      <label data-test-field="title">Title
        <@fields.title/>
      </label>
      <label data-test-field="description">Description
        <@fields.description/>
      </label>
    </div>
    <label data-test-field="ref">Ref
      <@fields.ref/>
    </label>
    <div>
      Demo: <@fields.demo/>
      <button {{on "click" (fn openCatalog @model.ref)}}>Choose Card</button>
    </div>
  </template>
}

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
  static edit = EditView;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div><@fields.title/></div>
      <div><@fields.description/></div>
      <div><@fields.ref/></div>
      <div><@fields.isPrimitive/></div>
      <div><@fields.demo/></div>
    </template>
  }
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div data-test-title><@fields.title/></div>
      <div data-test-description><@fields.description/></div>
      <div data-test-ref><@fields.ref/></div>
      <div><@fields.isPrimitive/></div>
      <div><@fields.demo/></div>
    </template>
  }
}