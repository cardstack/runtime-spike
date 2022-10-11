import { contains, field, Component, Card, primitive } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import BooleanCard from 'https://cardstack.com/base/boolean';
import CardRefCard from 'https://cardstack.com/base/card-ref';
import { baseCardRef } from "@cardstack/runtime-common";
import { initStyleSheet, attachStyles } from 'https://cardstack.com/base/attach-styles';

let css = `
  this {
    background-color: #cbf3f0;
    border: 1px solid gray; 
    border-radius: 10px; 
    padding: 1rem;
  }
  .demo {
    margin-top: 1rem;
  }
`;

let editCSS = `
  this {
    background-color: #cbf3f0;
    border: 1px solid gray; 
    border-radius: 10px; 
    padding: 1rem;
  }
  .edit-field {
    display: block;
    padding: 0.75rem;
    text-transform: capitalize;
    background-color: #ffffff6e;
    border: 1px solid gray;
    margin: 0.5rem 0;
  }
  input[type=text] {
    box-sizing: border-box;
    background-color: transparent;
    width: 100%;
    margin-top: .5rem;
    display: block;
    padding: 0.5rem;
    font: inherit;
    border: inherit;
  }
`;

let styles = initStyleSheet(css);
let editStyles = initStyleSheet(editCSS);

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
      <div {{attachStyles editStyles}}>
        <label class="edit-field" data-test-field="title">Title
          <@fields.title/>
        </label>
        <label class="edit-field" data-test-field="description">Description
          <@fields.description/>
        </label>
        <div class="edit-field" data-test-field="ref">Ref
          <@fields.ref/>
        </div>
        <div class="edit-field" data-test-field="demo">Demo
          <@fields.demo/>
        </div>
      </div>
    </template>
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div {{attachStyles styles}}>
        <h2><@fields.title/></h2>
        <div><@fields.ref/></div>
        {{#if @model.showDemo}}
          <div class="demo" data-test-demo-embedded><@fields.demo/></div>
        {{/if}}
      </div>
    </template>
  }
  
  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div {{attachStyles styles}}>
        <h1 data-test-title><@fields.title/></h1>
        <p data-test-description><em><@fields.description/></em></p>
        <div><@fields.ref/></div>
        {{#if @model.showDemo}}
          <div class="demo" data-test-demo><@fields.demo/></div>
        {{/if}}
      </div>
    </template>
  }
}