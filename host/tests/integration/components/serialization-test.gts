import { module, test, skip } from 'qunit';
import { setupRenderingTest } from 'ember-qunit';
import stringify from 'fast-json-stable-stringify'
import { renderCard } from '../../helpers/render-component';
import { contains, field, Component, Card, serializedGet, serializeCard } from 'runtime-spike/lib/card-api';
import StringCard from 'runtime-spike/lib/string';
import DateCard from 'runtime-spike/lib/date';
import DatetimeCard from 'runtime-spike/lib/datetime';
import parseISO from 'date-fns/parseISO';
import { p, cleanWhiteSpace } from '../../helpers';

module('Integration | serialization', function (hooks) {
  setupRenderingTest(hooks);

  test('can deserialize field', async function (assert) {
    class Post extends Card {
      @field title = contains(StringCard);
      @field created = contains(DateCard);
      @field published = contains(DatetimeCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template><@fields.title/> created <@fields.created/> published <@fields.published /></template>
      }
    }

    // initialize card data as serialized to force us to deserialize instead of using cached data
    let firstPost = Post.fromSerialized({ title: 'First Post', created: '2022-04-22', published: '2022-04-27T16:02' });
    await renderCard(firstPost, 'isolated');

    // the template value 'Apr 22, 2022' can only be realized when the card has
    // correctly deserialized it's static data property
    assert.strictEqual(cleanWhiteSpace(this.element.textContent!), 'First Post created Apr 22, 2022 published Apr 27, 2022, 4:02 PM');
  });

  test('can serialize field', async function(assert) {
    class Post extends Card {
      @field title = contains(StringCard);
      @field created = contains(DateCard);
      @field published = contains(DatetimeCard);
      static isolated = class Isolated extends Component<typeof this> {
        <template>created {{serializedGet @model 'created'}}, published {{serializedGet @model 'published'}}</template>
      }
    }

    // initialize card data as deserialized to force us to serialize instead of using cached data
    let firstPost =  new Post({ title: 'First Post', created: p('2022-04-22'), published: parseISO('2022-04-27T16:30+00:00') });
    await renderCard(firstPost, 'isolated');
    assert.strictEqual(cleanWhiteSpace(this.element.textContent!), 'created 2022-04-22, published 2022-04-27T16:30:00.000Z');
  });

  test('can deserialize a nested field', async function(assert) {
    class Person extends Card {
      @field firstName = contains(StringCard);
      @field birthdate = contains(DateCard);
      @field lastLogin = contains(DatetimeCard);
    }

    class Post extends Card {
      @field title = contains(StringCard);
      @field author = contains(Person);
      static isolated = class Isolated extends Component<typeof this> {
        <template>birthdate <@fields.author.birthdate/> last login <@fields.author.lastLogin/></template>
      }
    }

    let firstPost = Post.fromSerialized({ title: 'First Post', author: { firstName: 'Mango', birthdate: '2019-10-30', lastLogin: '2022-04-27T16:58' } });
    await renderCard(firstPost, 'isolated');
    assert.strictEqual(cleanWhiteSpace(this.element.textContent!), 'birthdate Oct 30, 2019 last login Apr 27, 2022, 4:58 PM');
  });

  test('can deserialize a composite field', async function(assert) {
    class Person extends Card {
      @field firstName = contains(StringCard);
      @field birthdate = contains(DateCard);
      @field lastLogin = contains(DatetimeCard);
      static embedded = class Embedded extends Component<typeof this> {
        <template><@fields.firstName/> born on: <@fields.birthdate/> last logged in: <@fields.lastLogin/></template>
      }
    }

    class Post extends Card {
      @field title = contains(StringCard);
      @field author = contains(Person);
      static isolated = class Isolated extends Component<typeof this> {
        <template><@fields.author/></template>
      }
    }

    let firstPost = Post.fromSerialized({ title: 'First Post', author: { firstName: 'Mango', birthdate: '2019-10-30', lastLogin: '2022-04-27T17:00' } });
    await renderCard(firstPost, 'isolated');
    assert.strictEqual(cleanWhiteSpace(this.element.textContent!), 'Mango born on: Oct 30, 2019 last logged in: Apr 27, 2022, 5:00 PM');
  });

  test('can serialize a composite field', async function(assert) {
    class Animal extends Card {
      @field species = contains(StringCard);
    }

    class Person extends Animal {
      @field firstName = contains(StringCard);
      @field birthdate = contains(DateCard);
      @field lastLogin = contains(DatetimeCard);
    }

    class Post extends Card {
      @field title = contains(StringCard);
      @field author = contains(Person);
      static isolated = class Isolated extends Component<typeof this> {
        <template>{{stringify (serializedGet @model 'author')}}</template>
      }
    }

    let firstPost = new Post({ title: 'First Post', author: { firstName: 'Mango', birthdate: p('2019-10-30'), species: 'canis familiaris', lastLogin: parseISO('2022-04-27T16:30+00:00') } });
    await renderCard(firstPost, 'isolated');
    assert.strictEqual(this.element.textContent!.trim(), `{"birthdate":"2019-10-30","firstName":"Mango","lastLogin":"2022-04-27T16:30:00.000Z","species":"canis familiaris"}`);
  });

  test('can serialize a computed field', async function(assert) {
    class Person extends Card {
      @field birthdate = contains(DateCard);
      @field firstBirthday = contains(DateCard, { computeVia:
        function(this: Person) {
          return new Date(this.birthdate.getFullYear() + 1, this.birthdate.getMonth(), this.birthdate.getDate());
        }
      });
      static isolated = class Isolated extends Component<typeof this> {
        <template>{{serializedGet @model 'firstBirthday'}}</template>
      }
    }

    let mango =  Person.fromSerialized({ birthdate: p('2019-10-30') });
    await renderCard(mango, 'isolated');
    assert.strictEqual(this.element.textContent!.trim(), '2020-10-30');
  });

  skip('can deserialize a containsMany field');
  skip('can serialize a containsMany field');

  test('can serialize a card with primitive fields', async function (assert) {
    class Post extends Card {
      @field title = contains(StringCard);
      @field created = contains(DateCard);
      @field published = contains(DatetimeCard);
    }
    let firstPost = new Post({ title: 'First Post', created: p('2022-04-22'), published: parseISO('2022-04-27T16:30+00:00') });
    await renderCard(firstPost, 'isolated');
    let payload = serializeCard(firstPost);
    assert.deepEqual(
      payload as any,
      {
        type: 'post',
        attributes: {
          title: 'First Post',
          created: '2022-04-22',
          published: '2022-04-27T16:30:00.000Z',
        },
      },
      'A model can be serialized once instantiated'
    );
  });

  test('can serialize a card with composite field', async function (assert) {
    class Animal extends Card {
      @field species = contains(StringCard);
    }
    class Person extends Animal {
      @field firstName = contains(StringCard);
      @field birthdate = contains(DateCard);
    }
    class Post extends Card {
      @field title = contains(StringCard);
      @field author = contains(Person);
    }
    let firstPost = new Post({ title: 'First Post', author: { firstName: 'Mango', birthdate: p('2019-10-30'), species: 'canis familiaris' } });
    await renderCard(firstPost, 'isolated');
    let payload = serializeCard(firstPost);
    assert.deepEqual(
      payload as any,
      {
        type: 'post',
        attributes: {
          title: 'First Post',
          author: {
            firstName: 'Mango',
            birthdate: '2019-10-30',
            species: 'canis familiaris',
          }
        },
      }
    );
  });

  test('can serialize a card with computed field', async function (assert) {
    class Person extends Card {
      @field birthdate = contains(DateCard);
      @field firstBirthday = contains(DateCard, { computeVia:
        function(this: Person) {
          return new Date(this.birthdate.getFullYear() + 1, this.birthdate.getMonth(), this.birthdate.getDate());
        }
      });
    }
    let mango = new Person({ birthdate: p('2019-10-30') });
    await renderCard(mango, 'isolated');
    let payload = serializeCard(mango);
    assert.deepEqual(
      payload as any,
      {
        type: 'person',
        attributes: {
          birthdate: '2019-10-30',
          firstBirthday: '2020-10-30',
        },
      }
    );
  });
});
