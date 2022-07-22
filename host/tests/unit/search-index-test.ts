import { module, test } from 'qunit';
import { TestRealm, TestRealmAdapter } from '../helpers';
import { RealmPaths } from '@cardstack/runtime-common/paths';
import { SearchIndex } from '@cardstack/runtime-common/search-index';

let paths = new RealmPaths('http://test-realm');

module('Unit | search-index', function () {
  test('full indexing discovers card instances', async function (assert) {
    let adapter = new TestRealmAdapter({
      'empty.json': {
        data: {
          type: 'card',
          attributes: {},
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/card-api',
              name: 'Card',
            },
          },
        },
      },
    });
    let realm = TestRealm.createWithAdapter(adapter);
    let indexer = realm.searchIndex;
    await indexer.run();
    let cards = await indexer.search({});
    assert.deepEqual(cards, [
      {
        id: 'http://test-realm/empty',
        type: 'card',
        attributes: {},
        meta: {
          adoptsFrom: {
            module: 'https://cardstack.com/base/card-api',
            name: 'Card',
          },
          lastModified: adapter.lastModified.get(
            paths.fileURL('empty.json').href
          ),
        },
      },
    ]);
  });

  test('full indexing identifies the exported cards in a module', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(StringCard);
        }

        export class FancyPerson extends Person {
          @field favoriteColor = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    let refs = await indexer.exportedCardsOf('person.gts');
    assert.deepEqual(refs, [
      {
        type: 'exportedCard',
        module: 'http://test-realm/person.gts',
        name: 'FancyPerson',
      },
    ]);
  });

  test('full indexing discovers card source where super class card comes from outside local realm', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();

    let definition = await indexer.typeOf({
      type: 'exportedCard',
      module: 'person.gts',
      name: 'Person',
    });
    assert.deepEqual(definition?.id, {
      type: 'exportedCard',
      module: 'http://test-realm/person.gts',
      name: 'Person',
    });
    assert.deepEqual(definition?.super, {
      type: 'exportedCard',
      module: 'https://cardstack.com/base/card-api',
      name: 'Card',
    });
    assert.deepEqual(definition?.fields.get('firstName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
    assert.deepEqual(definition?.fields.get('lastName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
  });

  test('full indexing discovers card source where super class card comes from different module in the local realm', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(StringCard);
        }
      `,
      'fancy-person.gts': `
        import { contains, field } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';
        import { Person } from './person';

        export class FancyPerson extends Person {
          @field favoriteColor = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    let definition = await indexer.typeOf({
      type: 'exportedCard',
      module: 'fancy-person.gts',
      name: 'FancyPerson',
    });
    assert.deepEqual(definition?.id, {
      type: 'exportedCard',
      module: 'http://test-realm/fancy-person.gts',
      name: 'FancyPerson',
    });
    assert.deepEqual(definition?.super, {
      type: 'exportedCard',
      module: 'http://test-realm/person', // this does not have the ".gts" extension because we import it as just "./person"
      name: 'Person',
    });

    assert.deepEqual(definition?.fields.get('lastName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });

    assert.deepEqual(definition?.fields.get('favoriteColor'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
  });

  test('full indexing discovers card source where super class card comes same module', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(StringCard);
        }

        export class FancyPerson extends Person {
          @field favoriteColor = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    let definition = await indexer.typeOf({
      type: 'exportedCard',
      module: 'person.gts',
      name: 'FancyPerson',
    });
    assert.deepEqual(definition?.id, {
      type: 'exportedCard',
      module: 'http://test-realm/person.gts',
      name: 'FancyPerson',
    });
    assert.deepEqual(definition?.super, {
      type: 'exportedCard',
      module: 'http://test-realm/person.gts',
      name: 'Person',
    });
    assert.deepEqual(definition?.fields.get('lastName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
    assert.deepEqual(definition?.fields.get('favoriteColor'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
  });

  test('full indexing discovers internal cards that are consumed by an exported card', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(StringCard);
        }

        export class FancyPerson extends Person {
          @field favoriteColor = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    let definition = await indexer.typeOf({
      type: 'ancestorOf',
      card: {
        type: 'exportedCard',
        module: 'person.gts',
        name: 'FancyPerson',
      },
    });
    assert.deepEqual(definition?.id, {
      type: 'ancestorOf',
      card: {
        type: 'exportedCard',
        module: 'http://test-realm/person.gts',
        name: 'FancyPerson',
      },
    });
    assert.deepEqual(definition?.super, {
      type: 'exportedCard',
      module: 'https://cardstack.com/base/card-api',
      name: 'Card',
    });
    assert.deepEqual(definition?.fields.get('firstName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
    assert.strictEqual(
      definition?.fields.get('favoriteColor'),
      undefined,
      'favoriteColor field does not exist on card'
    );
  });

  test('full indexing ignores card source where super class in a different module is not actually a card', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        class NotACard {};

        export class Person extends NotACard {
          @field firstName = contains(StringCard);
          @field lastName = contains(StringCard);
        }
      `,
      'fancy-person.gts': `
        import { contains, field } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';
        import { Person } from './person';

        export class FancyPerson extends Person {
          @field favoriteColor = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    assert.strictEqual(
      await indexer.typeOf({
        type: 'exportedCard',
        module: 'fancy-person.gts',
        name: 'FancyPerson',
      }),
      undefined,
      'FancyPerson is not actually a card'
    );
  });

  test('full indexing ignores card source where the super class is in the same module and not actually a card', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        class NotACard {}

        export class FancyPerson extends NotACard {
          @field favoriteColor = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    assert.strictEqual(
      await indexer.typeOf({
        type: 'exportedCard',
        module: 'person.gts',
        name: 'FancyPerson',
      }),
      undefined,
      'FancyPerson is not actually a card'
    );
  });

  test('full indexing ignores cards that are not exported from their module', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    assert.strictEqual(
      await indexer.typeOf({
        type: 'exportedCard',
        module: 'person.gts',
        name: 'Person',
      }),
      undefined,
      'Person is not actually a card (that is exported)'
    );
  });

  test('full indexing ignores card source where super class is in a different realm, but the realm says that the export is not actually a card', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, NotACard } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        export class FancyPerson extends NotACard {
          @field favoriteColor = contains(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    assert.strictEqual(
      await indexer.typeOf({
        type: 'exportedCard',
        module: 'person.gts',
        name: 'FancyPerson',
      }),
      undefined,
      'FancyPerson is not actually a card'
    );
  });

  test('full indexing discovers internal field cards that are consumed by an exported card', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        class NewFieldCard extends Card {}

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(NewFieldCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    let definition = await indexer.typeOf({
      type: 'fieldOf',
      card: {
        type: 'exportedCard',
        module: 'person.gts',
        name: 'Person',
      },
      field: 'lastName',
    });
    assert.deepEqual(definition?.id, {
      type: 'fieldOf',
      card: {
        type: 'exportedCard',
        module: 'http://test-realm/person.gts',
        name: 'Person',
      },
      field: 'lastName',
    });
    assert.deepEqual(definition?.super, {
      type: 'exportedCard',
      module: 'https://cardstack.com/base/card-api',
      name: 'Card',
    });
    assert.strictEqual(definition?.fields.size, 0);

    let cardDefinition = await indexer.typeOf({
      type: 'exportedCard',
      module: 'person.gts',
      name: 'Person',
    });
    assert.deepEqual(cardDefinition?.fields.get('firstName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
    assert.deepEqual(cardDefinition?.fields.get('lastName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'fieldOf',
        card: {
          type: 'exportedCard',
          module: 'http://test-realm/person.gts',
          name: 'Person',
        },
        field: 'lastName',
      },
    });
  });

  test('full indexing ignores fields that are not actually fields', async function (assert) {
    let realm = TestRealm.create({
      'person.gts': `
        import { contains, field, Card, notAFieldDecorator, notAFieldType } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        class NotAFieldCard {}

        export class Person extends Card {
          @field firstName = contains(StringCard);
          @field lastName = contains(NotAFieldCard);
          @notAFieldDecorator notAField = contains(StringCard);
          @field alsoNotAField = notAFieldType(StringCard);
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    let definition = await indexer.typeOf({
      type: 'exportedCard',
      module: 'person.gts',
      name: 'Person',
    });
    assert.deepEqual(definition?.fields.get('firstName'), {
      fieldType: 'contains',
      fieldCard: {
        type: 'exportedCard',
        module: 'https://cardstack.com/base/string',
        name: 'default',
      },
    });
    assert.strictEqual(
      definition?.fields.get('lastName'),
      undefined,
      'lastName field does not exist'
    );
    assert.strictEqual(
      definition?.fields.get('notAField'),
      undefined,
      'notAField field does not exist'
    );
    assert.strictEqual(
      definition?.fields.get('alsoNotAField'),
      undefined,
      'alsoNotAField field does not exist'
    );
  });

  test('parses first-class template syntax', async function (assert) {
    let realm = TestRealm.create({
      'my-card.gts': `
        import { contains, field, Card, Component } from 'https://cardstack.com/base/card-api';
        import StringCard from 'https://cardstack.com/base/string';

        export class Person extends Card {
          @field firstName = contains(StringCard);

          static isolated = class Isolated extends Component<typeof this> {
            <template><div class="hi"><@fields.firstName /></div></template>
          }
        }
      `,
    });
    let indexer = realm.searchIndex;
    await indexer.run();
    let definition = await indexer.typeOf({
      type: 'exportedCard',
      module: 'my-card.gts',
      name: 'Person',
    });
    assert.ok(definition, 'got definition');
  });

  test('directories do not list entries that match patterns in ignore files', async function (assert) {
    const cardSource = `
      import { Card } from 'https://cardstack.com/base/card-api';
      export class Post extends Card {}
    `;

    let realm = TestRealm.create({
      'sample-post.json': '',
      'posts/1.json': '',
      'posts/nested.gts': cardSource,
      'posts/ignore-me.gts': cardSource,
      'posts/2.json': '',
      'post.gts': cardSource,
      'dir/card.gts': cardSource,
    });

    const listings = [
      {
        kind: 'file',
        name: 'sample-post.json',
      },
      {
        kind: 'directory',
        name: 'posts',
      },
      {
        kind: 'file',
        name: 'post.gts',
      },
      {
        kind: 'directory',
        name: 'dir',
      },
    ] as any;

    const ignoreFile = {
      name: '.gitignore',
      kind: 'file',
    };

    const nestedListings = [
      {
        name: '1.json',
        kind: 'file',
      },
      {
        name: 'nested.gts',
        kind: 'file',
      },
      {
        name: 'ignore-me.gts',
        kind: 'file',
      },
      {
        name: '2.json',
        kind: 'file',
      },
    ] as any;

    let indexer = realm.searchIndex;
    await indexer.run();

    let definition = await indexer.typeOf({
      type: 'exportedCard',
      module: 'posts/ignore-me.gts',
      name: 'Post',
    });
    assert.ok(definition, 'definition exists before file is ignored');

    let entries = await indexer.directory(new URL(realm.url));
    assert.deepEqual(entries, listings, 'top level entries are correct');
    let nestedEntries = await indexer.directory(new URL('posts/', realm.url));
    assert.deepEqual(
      nestedEntries,
      nestedListings,
      'nested entries are correct'
    );

    await realm.write('.gitignore', '*.json\n/dir\nposts/ignore-me.gts');

    let def = await indexer.typeOf({
      type: 'exportedCard',
      module: 'posts/ignore-me.gts',
      name: 'Post',
    });
    assert.strictEqual(
      def,
      undefined,
      'definition does not exist because file is ignored'
    );

    entries = await indexer.directory(new URL(realm.url));
    assert.deepEqual(
      entries,
      [...listings.slice(1, 3), ignoreFile],
      'correct file is hidden in top level'
    );

    nestedEntries = await indexer.directory(new URL('posts/', realm.url));
    assert.deepEqual(
      nestedEntries,
      [
        {
          name: 'nested.gts',
          kind: 'file',
        },
      ],
      'correct files are hidden in nested'
    );
  });

  module('query', function (hooks) {
    const sampleCards = {
      'card-1.json': {
        data: {
          type: 'card',
          attributes: {
            name: 'card 1',
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/card-api',
              name: 'Card',
            },
          },
        },
      },
      'cards/1.json': {
        data: {
          type: 'card',
          attributes: {
            name: 'card 1',
            description: 'first article',
            type: 'article',
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/card-api',
              name: 'Card',
            },
          },
        },
      },
      'cards/2.json': {
        data: {
          type: 'card',
          attributes: {
            name: 'card 2',
            type: 'article',
            author: {
              name: 'carl stack',
              email: 'carl@stack.com',
            },
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/card-api',
              name: 'Card',
            },
          },
        },
      },
    };

    let indexer: SearchIndex;

    hooks.beforeEach(async function () {
      let realm = TestRealm.create(sampleCards);
      indexer = realm.searchIndex;
      await indexer.run();
    });

    test('can filter cards by id', async function (assert) {
      let matching = await indexer.search({
        filter: {
          eq: {
            id: 'http://test-realm/card-1',
          },
        },
      });
      assert.strictEqual(matching.length, 1, 'found one card');
      assert.strictEqual(
        matching[0]?.id,
        'http://test-realm/card-1',
        'card id is correct'
      );
    });

    test('can use `eq` filter on multiple fields', async function (assert) {
      let matching = await indexer.search({
        filter: {
          eq: {
            'attributes.name': 'card 1',
            'attributes.type': 'article',
          },
        },
      });
      assert.strictEqual(matching.length, 1);
      assert.strictEqual(matching[0]?.id, 'http://test-realm/cards/1');
    });

    test('can filter on a deeply nested field using `eq`', async function (assert) {
      let matching = await indexer.search({
        filter: {
          eq: {
            'attributes.author.email': 'carl@stack.com',
          },
        },
      });
      assert.strictEqual(matching.length, 1);
      assert.strictEqual(matching[0]?.id, 'http://test-realm/cards/2');
    });
  });
});
