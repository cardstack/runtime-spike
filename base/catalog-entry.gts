import { contains, field, Component, Card, primitive } from 'https://cardstack.com/base/card-api';
import StringCard from 'https://cardstack.com/base/string';
import BooleanCard from 'https://cardstack.com/base/boolean';
import CardRefCard from 'https://cardstack.com/base/card-ref';
import { Loader } from "@cardstack/runtime-common";
import { ComponentLike } from '@glint/template';
import { tracked } from '@glimmer/tracking';
import { task } from 'ember-concurrency';
import { render } from "./render-card";
import { taskFor } from 'ember-concurrency-ts';

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
      Demo:
      {{#if this.rendered.component}}
        <this.rendered.component/>
      {{/if}}
    </div>
  </template>

  @tracked component: ComponentLike<{ Args: {}; Blocks: {} }> | undefined;
  @tracked card: Card | undefined;
  rendered = render(this, () => this.card, () => 'edit');

  constructor(owner: unknown, args: any) {
    super(owner, args);
    taskFor(this.loadCard).perform();
  }

  @task private async loadCard(this: EditView) {
    if (!this.args.model) {
      return;
    }
    let module: Record<string, any> = await Loader.import(this.args.model.ref.module);
    let Clazz: typeof Card = module[this.args.model.ref.name];
    this.card = Clazz.fromSerialized({...(Clazz as any).demo ?? {}});
    this.args.model.demo = this.card;
  }
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
  @field demo = contains(Card, { computeVia: async function(this: CatalogEntry) {
    
    let module: Record<string, any> = await Loader.import(this.ref.module);
    let Clazz: typeof Card = module[this.ref.name];
    return Clazz.fromSerialized({...(Clazz as any).demo ?? {}});
  }});

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