import { module, test } from 'qunit';
import { cardSrc } from '@cardstack/runtime-common/etc/test-fixtures';
import { isCardDocument } from '@cardstack/runtime-common/search-index';
import { baseRealm } from '@cardstack/runtime-common';
import { TestRealm, TestRealmAdapter, testRealmURL } from '../helpers';

module('Unit | catalog-entry editor', function () {
  const catalogEntryData = {
    type: 'card',
    attributes: {
      title: 'Person',
      description: 'Catalog entry for Person card',
      ref: {
        module: `${testRealmURL}person.gts`,
        name: 'Person',
      },
    },
    meta: {
      adoptsFrom: {
        module: `${baseRealm.url}catalog-entry`,
        name: 'CatalogEntry',
      },
    },
  };

  test('can create new catalog entry', async function (assert) {
    let adapter = new TestRealmAdapter({ 'person.gts': cardSrc });
    let realm = TestRealm.createWithAdapter(adapter);
    await realm.ready;

    let response = await realm.handle(
      new Request(testRealmURL, {
        method: 'POST',
        headers: {
          Accept: 'application/vnd.api+json',
        },
        body: JSON.stringify({ data: catalogEntryData }, null, 2),
      })
    );
    assert.strictEqual(response.status, 201, 'successful http status');
    let json = await response.json();
    if (isCardDocument(json)) {
      assert.strictEqual(
        json.data.id,
        `${testRealmURL}CatalogEntry/1`,
        'the id is correct'
      );
      assert.ok(json.data.meta.lastModified, 'lastModified is populated');
      let fileRef = await adapter.openFile('CatalogEntry/1.json');
      if (!fileRef) {
        throw new Error('file not found');
      }
      assert.deepEqual(
        JSON.parse(fileRef.content as string),
        { data: catalogEntryData },
        'file contents are correct'
      );
    } else {
      assert.ok(false, 'response body is not a card document');
    }

    let searchIndex = realm.searchIndex;
    let card = await searchIndex.card(new URL(json.data.links.self));
    assert.strictEqual(
      card?.id,
      `${testRealmURL}CatalogEntry/1`,
      'found card in index'
    );
  });

  test('can edit catalog entry', async function (assert) {
    let adapter = new TestRealmAdapter({
      'person.gts': cardSrc,
      'CatalogEntry/1.json': { data: catalogEntryData },
    });
    let realm = TestRealm.createWithAdapter(adapter);
    await realm.ready;
    let response = await realm.handle(
      new Request(`${testRealmURL}CatalogEntry/1`, {
        method: 'PATCH',
        headers: {
          Accept: 'application/vnd.api+json',
        },
        body: JSON.stringify(
          {
            data: {
              type: 'card',
              attributes: {
                title: 'Author',
              },
              meta: {
                adoptsFrom: {
                  module: `${baseRealm.url}catalog-entry`,
                  name: 'CatalogEntry',
                },
              },
            },
          },
          null,
          2
        ),
      })
    );
    assert.strictEqual(response.status, 200, 'successful http status');
    let json = await response.json();
    if (isCardDocument(json)) {
      assert.strictEqual(
        json.data.id,
        `${testRealmURL}CatalogEntry/1`,
        'the id is correct'
      );
      assert.strictEqual(
        json.data.attributes?.title,
        'Author',
        'field value is correct'
      );
      assert.strictEqual(
        json.data.attributes?.description,
        'Catalog entry for Person card',
        'field value is correct'
      );
      assert.strictEqual(
        json.data.meta.lastModified,
        adapter.lastModified.get(`${testRealmURL}CatalogEntry/1.json`),
        'lastModified is correct'
      );
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
              title: 'Author',
              description: 'Catalog entry for Person card',
              ref: {
                module: `${testRealmURL}person.gts`,
                name: 'Person',
              },
            },
            meta: {
              adoptsFrom: {
                module: `${baseRealm.url}catalog-entry`,
                name: 'CatalogEntry',
              },
            },
          },
        },
        'file contents are correct'
      );
    } else {
      assert.ok(false, 'response body is not a card document');
    }
    let searchIndex = realm.searchIndex;
    let card = await searchIndex.card(new URL(json.data.links.self));
    assert.strictEqual(
      card?.id,
      `${testRealmURL}CatalogEntry/1`,
      'found card in index'
    );
    assert.strictEqual(
      card?.attributes?.title,
      'Author',
      'field value is correct'
    );
    let cards = await searchIndex.search({
      filter: {
        on: {
          module: `${baseRealm.url}catalog-entry`,
          name: 'CatalogEntry',
        },
        eq: { title: 'Author' },
      },
    });
    assert.strictEqual(cards.length, 1, 'search finds updated value');
  });
});
