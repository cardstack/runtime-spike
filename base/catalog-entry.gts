import { contains, field, Component, Card, primitive } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import BooleanCard from 'https://cardstack.com/base/boolean';
import CardRefCard from 'https://cardstack.com/base/card-ref';
import { baseCardRef } from "@cardstack/runtime-common";
import CardContainer from 'https://cardstack.com/base/card-container';

export class CatalogEntry extends Card {
  @field title = contains(StringCard);
  @field description = contains(StringCard);
  @field ref = contains(CardRefCard);
  @field isPrimitive = contains(BooleanCard, { computeVia: async function(this: CatalogEntry) {
    let module: Record<string, any> = await import(this.ref.module);
    let Clazz: typeof Card = module[this.ref.name];
    return primitive in Clazz ||
      // the base card is a special case where it is technically not a primitive, but because it has no fields
      // it is not useful to treat as a composite card (for the purposes of creating new card instances).
      (baseCardRef.module === this.ref.module && baseCardRef.name === this.ref.name);
  }});
  @field demo = contains(Card);

  get showDemo() {
    return !this.isPrimitive;
  }

  // An explicit edit template is provided since computed isPrimitive bool
  // field (which renders in the embedded format) looks a little wonky
  // right now in the edit view.
  static edit = class Edit extends Component<typeof this> {
    <template>
      <CardContainer @label={{@model.constructor.name}} class="card-edit">
        <label data-test-field="title">Title
          <@fields.title/>
        </label>
        <label data-test-field="description">Description
          <@fields.description/>
        </label>
        <div class="field" data-test-field="ref">Ref
          <@fields.ref/>
        </div>
        <div class="field" data-test-field="demo">Demo
          <@fields.demo/>
        </div>
      </CardContainer>
    </template>
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <CardContainer @label={{@model.constructor.name}}>
        <h3><@fields.title/></h3>
        <p><em><@fields.description/></em></p>
        <div><@fields.ref/></div>
        {{#if @model.showDemo}}
          <div data-test-demo-embedded><@fields.demo/></div>
        {{/if}}
      </CardContainer>
    </template>
  }
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <CardContainer @label={{@model.constructor.name}}>
        <h1 data-test-title><@fields.title/></h1>
        <p data-test-description><em><@fields.description/></em></p>
        <div><@fields.ref/></div>
        {{#if @model.showDemo}}
          <div data-test-demo><@fields.demo/></div>
        {{/if}}
      </CardContainer>
    </template>
  }
}