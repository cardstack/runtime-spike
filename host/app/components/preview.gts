import Component from '@glimmer/component';
import AnimationContext from 'animations-experiment/components/animation-context';
import sprite from 'animations-experiment/modifiers/sprite';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import SpringBehavior from 'animations-experiment/behaviors/spring';
import type { Changeset } from 'animations-experiment/models/changeset';
import type { AnimationDefinition } from 'animations-experiment/models/transition-runner';
import type { Card, Format } from 'https://cardstack.com/base/card-api';

interface Signature {
  Args: {
    card: Card;
    format?: Format;
  }
}

function a(thing: any){ return [thing] }

export default class Preview extends Component<Signature> {
  <template>
    <button {{on 'click' this.toggle}}>Toggle</button>
    <AnimationContext @use={{this.transition}} >
      {{#if this.mode}}
        <div {{sprite id="first"}} style="background-color: red; width: 500px; height: 500px"></div>
      {{else}}
        <div {{sprite id="first"}} style="background-color: red; width: 200px; height: 200px"></div>        
      {{/if}}
      {{!-- {{#each (a this.renderedCard) as |Rc|}}
        <div {{sprite id="first"}} >
          <Rc />
        </div>
      {{/each}} --}}
    </AnimationContext>
    <this.renderedCard/>
  </template>

  toggle = () => this.mode = !this.mode;
  @tracked mode = true;

  transition = (changeset: Changeset): AnimationDefinition => {
    return {
      timeline: {
        type: 'parallel',
        animations: [
          {
            sprites: changeset.keptSprites,
            properties: {
              size: {}
            },
            timing: {
              behavior: new SpringBehavior()
            }
          }
        ]
      }
    }
  }

  get renderedCard() {
    return this.args.card.constructor.getComponent(this.args.card, this.args.format ?? 'isolated');
  }
}
