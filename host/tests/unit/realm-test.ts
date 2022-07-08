import { module, test } from 'qunit';
import { isCardDocument } from '@cardstack/runtime-common/search-index';
import { Dir, createTestRealm } from '../helpers';

module('Unit | realm', function () {
  test('realm can serve card data requests', async function (assert) {
    let realm = createTestRealm({
      'dir/empty.json': {
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
    await realm.ready;

    let response = await realm.handle(
      new Request('http://test-realm/dir/empty', {
        headers: {
          Accept: 'application/vnd.api+json',
        },
      })
    );

    assert.strictEqual(response.status, 200, 'successful http status');
    let json = await response.json();
    assert.deepEqual(json, {
      data: {
        type: 'card',
        id: 'http://test-realm/dir/empty',
        attributes: {},
        meta: {
          adoptsFrom: {
            module: 'https://cardstack.com/base/card-api',
            name: 'Card',
          },
          // lastModified: realm.lastModified.get('/dir/empty.json'),
        },
        links: {
          self: 'http://test-realm/dir/empty',
        },
      },
    });
    assert.ok(json.data.meta.lastModified, 'lastModified is populated');
  });

  test('realm can serve create card requests', async function (assert) {
    let realm = createTestRealm({});
    await realm.ready;
    {
      let response = await realm.handle(
        new Request('http://test-realm/', {
          method: 'POST',
          headers: {
            Accept: 'application/vnd.api+json',
          },
          body: JSON.stringify(
            {
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
            null,
            2
          ),
        })
      );
      assert.strictEqual(response.status, 201, 'successful http status');
      let json = await response.json();
      if (isCardDocument(json)) {
        assert.strictEqual(
          json.data.id,
          'http://test-realm/Card/1',
          'the id is correct'
        );
        assert.ok(json.data.meta.lastModified, 'lastModified is populated');
        assert.deepEqual(
          JSON.parse((realm.files?.Card as Dir)?.['1.json'] as string),
          {
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
          'file contents are correct'
        );
      } else {
        assert.ok(false, 'response body is not a card document');
      }

      let searchIndex = realm.searchIndex;
      let card = await searchIndex.card(new URL(json.data.links.self));
      assert.strictEqual(
        card?.id,
        'http://test-realm/Card/1',
        'found card in index'
      );
      let dirEntries = await searchIndex.directory(
        new URL('http://test-realm/Card/')
      );
      assert.deepEqual(
        dirEntries,
        [{ name: '1.json', kind: 'file' }],
        'found new file in directory entries'
      );
    }

    // create second file
    {
      let response = await realm.handle(
        new Request('http://test-realm/', {
          method: 'POST',
          headers: {
            Accept: 'application/vnd.api+json',
          },
          body: JSON.stringify(
            {
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
            null,
            2
          ),
        })
      );
      assert.strictEqual(response.status, 201, 'successful http status');
      let json = await response.json();
      if (isCardDocument(json)) {
        assert.strictEqual(
          json.data.id,
          'http://test-realm/Card/2',
          'the id is correct'
        );
        assert.ok(
          (realm.files?.Card as Dir)?.['2.json'],
          'file contents exist'
        );
      } else {
        assert.ok(false, 'response body is not a card document');
      }

      let searchIndex = realm.getSearchIndex();
      let card = await searchIndex.card(new URL(json.data.links.self));
      assert.strictEqual(
        card?.id,
        'http://test-realm/Card/2',
        'found card in index'
      );
      let dirEntries = await searchIndex.directory(
        new URL('http://test-realm/Card/')
      );
      assert.deepEqual(
        dirEntries,
        [
          { name: '1.json', kind: 'file' },
          { name: '2.json', kind: 'file' },
        ],
        'found new file in directory entries'
      );
    }
  });

  test('realm can serve patch card requests', async function (assert) {
    let realm = createTestRealm({
      'dir/card.json': {
        data: {
          type: 'card',
          attributes: {
            firstName: 'Mango',
            lastName: 'Abdel-Rahman',
          },
          meta: {
            adoptsFrom: {
              module: 'https://cardstack.com/base/card-api',
              name: 'Card',
            },
          },
        },
      },
    });
    await realm.ready;
    let response = await realm.handle(
      new Request('http://test-realm/dir/card', {
        method: 'PATCH',
        headers: {
          Accept: 'application/vnd.api+json',
        },
        body: JSON.stringify(
          {
            data: {
              type: 'card',
              attributes: {
                firstName: 'Van Gogh',
              },
              meta: {
                adoptsFrom: {
                  module: 'https://cardstack.com/base/card-api',
                  name: 'Card',
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
        'http://test-realm/dir/card',
        'the id is correct'
      );
      assert.strictEqual(
        json.data.attributes?.firstName,
        'Van Gogh',
        'field value is correct'
      );
      assert.strictEqual(
        json.data.attributes?.lastName,
        'Abdel-Rahman',
        'field value is correct'
      );
      assert.ok(json.data.meta.lastModified, 'lastModified is populated');
      assert.deepEqual(
        JSON.parse((realm.files?.dir as Dir)?.['card.json'] as string),
        {
          data: {
            type: 'card',
            attributes: {
              firstName: 'Van Gogh',
              lastName: 'Abdel-Rahman',
            },
            meta: {
              adoptsFrom: {
                module: 'https://cardstack.com/base/card-api',
                name: 'Card',
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
      'http://test-realm/dir/card',
      'found card in index'
    );
    assert.strictEqual(
      card?.attributes?.firstName,
      'Van Gogh',
      'field value is correct'
    );
    assert.strictEqual(
      card?.attributes?.lastName,
      'Abdel-Rahman',
      'field value is correct'
    );
    let dirEntries = await searchIndex.directory(
      new URL('http://test-realm/dir/')
    );
    assert.deepEqual(
      dirEntries,
      [{ name: 'card.json', kind: 'file' }],
      'directory entries is correct'
    );
  });
});
