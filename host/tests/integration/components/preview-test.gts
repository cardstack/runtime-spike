import { module, test } from 'qunit';
import GlimmerComponent from '@glimmer/component';
import { setupRenderingTest } from 'ember-qunit';
import { Loader, baseRealm, type ExistingCardArgs } from '@cardstack/runtime-common';
import Preview  from 'runtime-spike/components/preview';
import Service from '@ember/service';
import { renderComponent } from '../../helpers/render-component';
import { testRealmURL, shimModule } from '../../helpers';
import type { Format } from "https://cardstack.com/base/card-api";
import { waitFor, fillIn, click } from '../../helpers/shadow-assert';

let cardApi: typeof import("https://cardstack.com/base/card-api");
let string: typeof import ("https://cardstack.com/base/string");

class MockLocalRealm extends Service {
  isAvailable = true;
  url = new URL(testRealmURL);
}

const formats: Format[] = ['isolated', 'embedded', 'edit'];
module('Integration | preview', function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(async function () {
    Loader.destroy();
    Loader.addURLMapping(
      new URL(baseRealm.url),
      new URL('http://localhost:4201/base/')
    );
    cardApi = await Loader.import(`${baseRealm.url}card-api`);
    string = await Loader.import(`${baseRealm.url}string`);
    this.owner.register('service:local-realm', MockLocalRealm);
  });

  test('renders card', async function (assert) {
    let { field, contains, Card, Component } = cardApi;
    let { default: StringCard} = string;
    class TestCard extends Card {
      @field firstName = contains(StringCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template> <div data-test-firstName><@fields.firstName/></div> </template>
      }
    }
    await shimModule(`${testRealmURL}test-cards`, { TestCard });
    let json = {
      data: {
        attributes: { firstName: 'Mango' },
        meta: {
          adoptsFrom:
          {
            module: `${testRealmURL}test-cards`,
            name: 'TestCard'
          }
        }
      }
    };
    const args: ExistingCardArgs = { type: 'existing', json, url: `${testRealmURL}card` };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Preview @card={{args}} @formats={{formats}}/>
        </template>
      }
    )
    await waitFor('[data-test-firstName]'); // we need to wait for the card instance to load
    assert.shadowDOM('[data-test-firstName]').hasText('Mango');
  });

  test('can change card format', async function (assert) {
    let { field, contains, Card, Component } = cardApi;
    let { default: StringCard} = string;
    class TestCard extends Card {
      @field firstName = contains(StringCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template> <div data-test-isolated-firstName><@fields.firstName/></div> </template>
      }
      static embedded = class Embedded extends Component<typeof this> {
        <template> <div data-test-embedded-firstName><@fields.firstName/></div> </template>
      }
      static edit = class Edit extends Component<typeof this> {
        <template> <div data-test-edit-firstName><@fields.firstName/></div> </template>
      }
    }
    await shimModule(`${testRealmURL}test-cards`, { TestCard });

    let json = {
      data: {
        attributes: { firstName: 'Mango' },
        meta: {
          adoptsFrom:
          {
            module: `${testRealmURL}test-cards`,
            name: 'TestCard'
          }
        }
      }
    };
    const args: ExistingCardArgs = { type: 'existing', json, url: `${testRealmURL}card` };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Preview @card={{args}} @formats={{formats}}/>
        </template>
      }
    )
    await waitFor('[data-test-isolated-firstName]'); // we need to wait for the card instance to load
    assert.shadowDOM('[data-test-isolated-firstName]').hasText('Mango');
    assert.shadowDOM('[data-test-embedded-firstName]').doesNotExist();
    assert.shadowDOM('[data-test-edit-firstName]').doesNotExist();

    await click('.format-button.embedded')
    assert.shadowDOM('[data-test-isolated-firstName]').doesNotExist();
    assert.shadowDOM('[data-test-embedded-firstName]').hasText('Mango');
    assert.shadowDOM('[data-test-edit-firstName]').doesNotExist();

    await click('.format-button.edit')
    assert.shadowDOM('[data-test-isolated-firstName]').doesNotExist();
    assert.shadowDOM('[data-test-embedded-firstName]').doesNotExist();
    assert.shadowDOM('[data-test-edit-firstName] input').hasValue('Mango');
  });

  test('edited card data in visible in different formats', async function (assert) {
    let { field, contains, Card, Component } = cardApi;
    let { default: StringCard} = string;
    class TestCard extends Card {
      @field firstName = contains(StringCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template> <div data-test-isolated-firstName><@fields.firstName/></div> </template>
      }
      static embedded = class Embedded extends Component<typeof this> {
        <template> <div data-test-embedded-firstName><@fields.firstName/></div> </template>
      }
      static edit = class Edit extends Component<typeof this> {
        <template> <div data-test-edit-firstName><@fields.firstName/></div> </template>
      }
    }
    await shimModule(`${testRealmURL}test-cards`, { TestCard });
    let json = {
      data: {
        attributes: { firstName: 'Mango' },
        meta: {
          adoptsFrom:
          {
            module: `${testRealmURL}test-cards`,
            name: 'TestCard'
          }
        }
      }
    };
    const args: ExistingCardArgs = { type: 'existing', json, url: `${testRealmURL}card` };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Preview @card={{args}} @formats={{formats}}/>
        </template>
      }
    )

    await click('.format-button.edit')
    await waitFor('[data-test-edit-firstName] input'); // we need to wait for the card instance to load
    await fillIn('[data-test-edit-firstName] input', 'Van Gogh');

    await click('.format-button.embedded');
    assert.shadowDOM('[data-test-embedded-firstName]').hasText('Van Gogh');

    await click('.format-button.isolated');
    assert.shadowDOM('[data-test-isolated-firstName]').hasText('Van Gogh');
  });

  test('can detect when card is dirty', async function(assert) {
    let { field, contains, Card, Component } = cardApi;
    let { default: StringCard} = string;
    class Person extends Card {
      @field firstName = contains(StringCard);
      static embedded = class Embedded extends Component<typeof this> {
        <template><@fields.firstName /></template>
      }
    }

    class Post extends Card{
      @field title = contains(StringCard);
      @field author = contains(Person);
      @field nickName = contains(StringCard, {
        computeVia: function(this: Post) {
          return this.author.firstName + '-poo';
        }
      });
    }
    await shimModule(`${testRealmURL}test-cards`, { Person, Post });

    let json = {
      data: {
        attributes: {
          author: {
            firstName: 'Mango',
          },
          title: 'We Need to Go to the Dog Park Now!'
        },
        meta: {
          adoptsFrom:
          {
            module: `${testRealmURL}test-cards`,
            name: 'Post'
          }
        }
      }
    };
    const args: ExistingCardArgs = { type: 'existing', json, url: `${testRealmURL}card` };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <Preview @card={{args}} @formats={{formats}}/>
        </template>
      }
    )

    await click('.format-button.edit')
    assert.shadowDOM('[data-test-save-card]').doesNotExist();
    assert.shadowDOM('[data-test-reset]').doesNotExist();

    await waitFor('[data-test-field="title"] input'); // we need to wait for the card instance to load
    await fillIn('[data-test-field="title"] input', 'Why I Whine'); // dirty top level field
    assert.shadowDOM('[data-test-field="title"] input').hasValue('Why I Whine');
    assert.shadowDOM('[data-test-save-card]').exists();
    assert.shadowDOM('[data-test-reset]').exists();

    await click('[data-test-reset]');
    assert.shadowDOM('[data-test-save-card]').doesNotExist();
    assert.shadowDOM('[data-test-reset]').doesNotExist();
    assert.shadowDOM('[data-test-field="title"] input').hasValue('We Need to Go to the Dog Park Now!');


    await fillIn('[data-test-field="firstName"] input', 'Van Gogh'); // dirty nested field
    assert.shadowDOM('[data-test-field="firstName"] input').hasValue('Van Gogh');
    assert.shadowDOM('[data-test-save-card]').exists();
    assert.shadowDOM('[data-test-reset]').exists();

    await click('[data-test-reset]');
    assert.shadowDOM('[data-test-save-card]').doesNotExist();
    assert.shadowDOM('[data-test-reset]').doesNotExist();
    assert.shadowDOM('[data-test-field="firstName"] input').hasValue('Mango');
  });
});
