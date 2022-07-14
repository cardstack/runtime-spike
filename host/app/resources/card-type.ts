import { Resource, useResource } from 'ember-resources';
import { restartableTask } from 'ember-concurrency';
import { taskFor } from 'ember-concurrency-ts';
import { tracked } from '@glimmer/tracking';
import { CardRef } from '@cardstack/runtime-common';
import { stringify } from 'qs';
import { service } from '@ember/service';
import LocalRealm from '../services/local-realm';

interface Args {
  named: { ref: CardRef };
}

interface Type {
  id: string;
  super: Type | undefined;
  fields: { name: string; card: Type; type: 'contains' | 'containsMany' }[];
}

interface DefinitionResource {
  id: string;
  relationships: {
    [fieldName: string]: {
      links: {
        related: string;
      };
      meta: {
        type: 'super' | 'contains' | 'containsMany';
      };
    };
  };
}

export class CardType extends Resource<Args> {
  @tracked type: Type | undefined;
  @service declare localRealm: LocalRealm;
  @tracked localRealmURL: URL;

  constructor(owner: unknown, args: Args) {
    super(owner, args);
    if (!this.localRealm.isAvailable) {
      throw new Error('Local realm is not available');
    }
    this.localRealmURL = this.localRealm.url;
    let { ref } = args.named;
    taskFor(this.assembleType).perform(ref);
  }

  @restartableTask private async assembleType(ref: CardRef) {
    let url = `${this.localRealmURL.href}_typeOf?${stringify(ref)}`;
    this.type = await this.makeCardType(url);
  }

  private async makeCardType(typeOfURL: string): Promise<Type> {
    let def = await this.load(typeOfURL);
    return {
      id: def.id,
      super: def.relationships._super
        ? await this.makeCardType(def.relationships._super.links.related)
        : undefined,
      fields: (
        await Promise.all(
          Object.entries(
            def.relationships as DefinitionResource['relationships']
          ).map(async ([fieldName, fieldDef]) => {
            if (fieldName === '_super') {
              return undefined;
            }
            return {
              name: fieldName,
              card: await this.makeCardType(fieldDef.links.related),
              type: fieldDef.meta.type,
            };
          })
        )
      ).filter(Boolean) as Type['fields'],
    };
  }

  private async load(typeOfURL: string): Promise<DefinitionResource> {
    let response = await fetch(typeOfURL, {
      headers: {
        Accept: 'application/vnd.api+json',
      },
    });

    let json = await response.json();
    return json.data as DefinitionResource;
  }
}

export function getCardType(parent: object, ref: () => CardRef) {
  return useResource(parent, CardType, () => ({
    named: { ref: ref() },
  }));
}
