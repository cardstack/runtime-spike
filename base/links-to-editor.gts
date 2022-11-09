import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { restartableTask } from 'ember-concurrency';
import { taskFor } from 'ember-concurrency-ts';
import { getBoxComponent } from 'field-component';
import {
  type Card,
  type Box,
  type Field
} from './card-api';
import {
  Loader,
  chooseCard,
  baseCardRef,
} from '@cardstack/runtime-common';
import type { ComponentLike } from '@glint/template';


interface Signature {
  Args: {
    model: Box<Card | null>;
    field: Field<typeof Card>;
  }
}
class LinksToEditor extends GlimmerComponent<Signature> {
  <template>
    <button {{on "click" this.choose}} data-test-choose-card>Choose</button>
    <button {{on "click" this.remove}} data-test-remove-card disabled={{this.isEmpty}}>Remove</button>
    {{#if this.isEmpty}}
      <div data-test-empty-link>[empty]</div>
    {{else}}
      <this.linkedCard/>
    {{/if}}
  </template>

  choose = () => {
    taskFor(this.chooseCard).perform();
  }

  remove = () => {
    this.args.model.value = null;
  }

  get isEmpty() {
    return this.args.model.value == null;
  }

  get linkedCard() {
    if (this.args.model.value == null) {
      throw new Error(`can't make field component with box value of null for field ${this.args.field.name}`);
    }
    let card = Reflect.getPrototypeOf(this.args.model.value)!.constructor as typeof Card;
    return getBoxComponent(card, 'embedded', this.args.model as Box<Card>);
  }

  @restartableTask private async chooseCard(this: LinksToEditor) {
    let currentlyChosen = !this.isEmpty ? (this.args.model.value as any)["id"] as string : undefined;
    let type = Loader.identify(this.args.field.card) ?? baseCardRef;
    let chosenCard = await chooseCard(
      {
        filter: {
          every: [
            { type },
            // omit the currently chosen card from the chooser
            ...(currentlyChosen ? [{
              not: {
                eq: { id: currentlyChosen },
                on: baseCardRef,
              }
            }] : [])
          ]
        }
      }
    );
    if (chosenCard) {
      this.args.model.value = chosenCard;
    }
  }
};

export function getLinksToEditor(
  model: Box<Card>,
  field: Field<typeof Card>,
): ComponentLike<{ Args: {}, Blocks: {} }> {
  return class LinksToEditTemplate extends GlimmerComponent {
    <template>
      <LinksToEditor @model={{model}} @field={{field}} />
    </template>
  };
}