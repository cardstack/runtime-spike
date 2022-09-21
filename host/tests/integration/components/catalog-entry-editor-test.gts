import { module, test } from 'qunit';
import GlimmerComponent from '@glimmer/component';
import { baseRealm, ExportedCardRef } from '@cardstack/runtime-common';
import { Loader } from "@cardstack/runtime-common/loader";
import { Realm } from "@cardstack/runtime-common/realm";
import { Deferred } from "@cardstack/runtime-common/deferred";
import { setupRenderingTest } from 'ember-qunit';
import { renderComponent } from '../../helpers/render-component';
import CatalogEntryEditor from 'runtime-spike/components/catalog-entry-editor';
import Service from '@ember/service';
import { waitUntil, click, fillIn } from '@ember/test-helpers';
import { TestRealm, TestRealmAdapter, testRealmURL } from '../../helpers';

class MockLocalRealm extends Service {
  isAvailable = true;
  url = new URL(testRealmURL);
}

class MockRouter extends Service {
  assert: Assert | undefined;
  expectedRoute: any | undefined;
  deferred: Deferred<void> | undefined;
  initialize(assert: Assert, expectedRoute: any, deferred: Deferred<void>) {
    this.assert = assert;
    this.expectedRoute = expectedRoute;
    this.deferred = deferred;
  }
  transitionTo(route: any) {
    this.assert!.deepEqual(route, this.expectedRoute, 'the route transitioned correctly')
    this.deferred!.fulfill();
  }
}

module('Integration | catalog-entry-editor', function (hooks) {
  let adapter: TestRealmAdapter
  let realm: Realm;
  setupRenderingTest(hooks);

  hooks.beforeEach(async function() {
    Loader.destroy();
    Loader.addURLMapping(
      new URL(baseRealm.url),
      new URL('http://localhost:4201/base/')
    );

    // We have a bit of a chicken and egg problem here in that in order for us
    // to short circuit the fetch we need a Realm instance, however, we can't
    // create a realm instance without first doing a full index which will load
    //  cards for any instances it find which results in a fetch. so we create
    // an empty index, and then just use realm.write() to incrementally add
    // items into our index.
    adapter = new TestRealmAdapter({});

    realm = TestRealm.createWithAdapter(adapter);
    Loader.addRealmFetchOverride(realm);
    await realm.ready;

    await realm.write('pet.gts', `
      import { contains, field, Component, Card } from "https://cardstack.com/base/card-api";
      import StringCard from "https://cardstack.com/base/string";
      import BooleanCard from "https://cardstack.com/base/boolean";
      export class Pet extends Card {
        @field name = contains(StringCard);
        @field lovesWalks = contains(BooleanCard);
        static isolated = class Isolated extends Component<typeof this> {
          <template><h1><@fields.name/></h1><@fields.lovesWalks/></template>
        }
        static embedded = class Embedded extends Component<typeof this> {
          <template><@fields.name/></template>
        }
      }
    `);

    this.owner.register('service:local-realm', MockLocalRealm);
    this.owner.register('service:router', MockRouter);
  });

  hooks.afterEach(function() {
    Loader.destroy();
  });

  test('can publish new catalog entry', async function (assert) {
    let router = this.owner.lookup('service:router') as MockRouter;
    let deferred = new Deferred<void>();
    router.initialize(assert, { queryParams: { path: `${testRealmURL}CatalogEntry/1.json`}}, deferred);
    const args: ExportedCardRef =  { module: `${testRealmURL}pet`, name: 'Pet' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitUntil(() => Boolean(document.querySelector('button[data-test-catalog-entry-publish]')));
    await click('[data-test-catalog-entry-publish]');
    await waitUntil(() => Boolean(document.querySelector('[data-test-ref]')));

    assert.dom('[data-test-catalog-entry-editor] [data-test-field="title"] input').hasValue('Pet');
    assert.dom('[data-test-catalog-entry-editor] [data-test-field="description"] input').hasValue('Catalog entry for Pet card');
    assert.dom('[data-test-catalog-entry-editor] [data-test-ref]').containsText(`Module: ${testRealmURL}pet Name: Pet`);
    assert.dom('[data-test-field="demo"] [data-test-field="name"] input').hasText('');
    assert.dom('[data-test-field="demo"] [data-test-field="lovesWalks"] label:nth-of-type(2) input').isChecked();

    await fillIn('[data-test-catalog-entry-editor] [data-test-field="title"] input', 'Pet test');
    await fillIn('[data-test-catalog-entry-editor] [data-test-field="description"] input', 'Test description');
    await fillIn('[data-test-field="demo"] [data-test-field="name"] input', 'Jackie');
    await click('[data-test-field="demo"] [data-test-field="lovesWalks"] label:nth-of-type(1) input');

    await click('button[data-test-save-card]');

    await deferred.promise; // wait for the component to transition on save
    let entry = await realm.searchIndex.card(new URL(`${testRealmURL}CatalogEntry/1`));
    assert.ok(entry, 'the new catalog entry was created');

    let fileRef = await adapter.openFile('CatalogEntry/1.json');
    if (!fileRef) {
      throw new Error('file not found');
    }
    assert.deepEqual(
      JSON.parse(fileRef.content as string),
      {
        data: {
          type: 'card',
          attributes: {
            title: 'Pet test',
            description: 'Test description',
            ref: {
              module: `${testRealmURL}pet`,
              name: 'Pet'
            },
            demo: {
              name: 'Jackie',
              lovesWalks: true
            }
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/catalog-entry',
              name: 'CatalogEntry',
            },
            fields: {
              demo: {
                adoptsFrom: {
                  module: `${testRealmURL}pet`,
                  name: 'Pet',
                }
              }
            }
          },
        },
      },
      'file contents are correct'
    );
  });

  test('can edit existing catalog entry', async function (assert) {
    await realm.write('pet-catalog-entry.json', JSON.stringify({
      data: {
        type: 'card',
        attributes: {
          title: 'Pet',
          description: 'Catalog entry',
          ref: {
            module: `${testRealmURL}pet`,
            name: 'Pet'
          },
          demo: {
            name: 'Jackie',
            lovesWalks: true
          }
        },
        meta: {
          adoptsFrom: {
            module:`${baseRealm.url}catalog-entry`,
            name: 'CatalogEntry'
          },
          fields: {
            demo: {
              adoptsFrom: {
                module: `${testRealmURL}pet`,
                name: 'Pet',
              }
            }
          }
        }
      }
    }));

    const args: ExportedCardRef =  { module: `${testRealmURL}pet`, name: 'Pet' };
    await renderComponent(
      class TestDriver extends GlimmerComponent {
        <template>
          <CatalogEntryEditor @ref={{args}} />
        </template>
      }
    );

    await waitUntil(() => Boolean(document.querySelector('[data-test-ref]')));

    assert.dom('[data-test-catalog-entry-id]').hasText(`${testRealmURL}pet-catalog-entry`);
    assert.dom('[data-test-catalog-entry-editor] [data-test-field="title"] input').hasValue('Pet');
    assert.dom('[data-test-catalog-entry-editor] [data-test-field="description"] input').hasValue('Catalog entry');
    assert.dom('[data-test-catalog-entry-editor] [data-test-ref]').containsText(`Module: ${testRealmURL}pet Name: Pet`);
    assert.dom('[data-test-field="demo"] [data-test-field="name"] input').hasValue('Jackie');
    assert.dom('[data-test-field="demo"] [data-test-field="lovesWalks"] label:nth-of-type(1) input').isChecked();

    await fillIn('[data-test-catalog-entry-editor] [data-test-field="title"] input', 'test title');
    await fillIn('[data-test-catalog-entry-editor] [data-test-field="description"] input', 'test description');
    await fillIn('[data-test-field="demo"] [data-test-field="name"] input', 'Jackie Wackie');

    await click('button[data-test-save-card]');
    await waitUntil(() => !(document.querySelector('[data-test-saving]')));

    assert.dom('button[data-test-save-card]').doesNotExist();
    assert.dom('[data-test-title]').exists();
    assert.dom('[data-test-title]').containsText('test title');
    assert.dom('[data-test-description]').containsText('test description');
    assert.dom('[data-test-demo]').containsText('Jackie Wackie');

    let maybeError = await realm.searchIndex.card(new URL(`${testRealmURL}pet-catalog-entry`));
    if (maybeError?.type === 'error') {
      throw new Error(
        `unexpected error when getting card from index: ${maybeError.error.message}`
      );
    }
    let { entry } = maybeError!;
    assert.strictEqual(entry?.resource.attributes?.title, 'test title', 'catalog entry title was updated');
    assert.strictEqual(entry?.resource.attributes?.description, 'test description', 'catalog entry description was updated');
    assert.strictEqual(entry?.resource.attributes?.demo?.name, 'Jackie Wackie', 'demo name field was updated');
  });
});
