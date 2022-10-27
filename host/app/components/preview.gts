import Component from '@glimmer/component';
import type { Card, Format } from 'https://cardstack.com/base/card-api';
import AnimationContext from 'animations-experiment/components/animation-context';
import sprite from 'animations-experiment/modifiers/sprite';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import SpringBehavior from 'animations-experiment/behaviors/spring';

interface Signature {
  Args: {
    card: Card;
    format?: Format;
  }
}

function a(thing){ return [thing] }

export default class Preview extends Component<Signature> {
  toggle = () => this.mode = !this.mode;
  @tracked mode = true;

  transition = (changeset) => {
    return {
      timeline: {
        parallel: [
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

  <template>
    <button {{on 'click' this.toggle}}>Toggle</button>
    <AnimationContext @use={{this.transition}} >
      {{!-- {{#if this.mode}}
        <div {{sprite id="first"}} style="background-color: red; width: 500px; height: 500px"></div>
      {{else}}
        <div {{sprite id="first"}} style="background-color: red; width: 200px; height: 200px"></div>        
      {{/if}} --}}
      {{#each (a this.renderedCard) as |Rc|}}
        <div {{sprite id="first"}} >
          <Rc />
        </div>
      {{/each}}
    </AnimationContext>
  </template>

  get renderedCard() {
    return this.args.card.constructor.getComponent(this.args.card, this.args.format ?? 'isolated');
  }
}
