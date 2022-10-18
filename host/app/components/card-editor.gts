import Component from '@glimmer/component';
//@ts-ignore cached not available yet in definitely typed
import { cached } from '@glimmer/tracking';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
// import isEqual from 'lodash/isEqual';
import { restartableTask } from 'ember-concurrency';
import { taskFor } from 'ember-concurrency-ts';
import { registerDestructor } from '@ember/destroyable';
import { service } from '@ember/service';
import LoaderService from '../services/loader-service';
import { importResource } from '../resources/import';
import { LooseSingleCardDocument, isSingleCardDocument, baseRealm } from '@cardstack/runtime-common';
import type { Format } from 'https://cardstack.com/base/card-api';
import type LocalRealm from '../services/local-realm';
import Preview from './preview';
import type { Card } from 'https://cardstack.com/base/card-api';

type CardAPI = typeof import('https://cardstack.com/base/card-api');

interface Signature {
  Args: {
    card: Card;
    selectedFormat?: Format;
    formats?: Format[];
    onCancel?: () => void;
    onSave?: (card: Card) => void;
  }
}

export default class CardEditor extends Component<Signature> {
  <template>
    <Preview
      @formats={{@formats}}
      @selectedFormat={{this.format}}
      @card={{@card}}
    />

    {{!-- @glint-ignore glint doesn't know about EC task properties --}}
    {{#if this.write.last.isRunning}}
      <span data-test-saving>Saving...</span>
    {{else}}
      {{#if this.isDirty}}
        <div>
          <button data-test-save-card {{on "click" this.save}} type="button">Save</button>
          {{#unless @card.id}}
            <button data-test-cancel-create {{on "click" this.cancel}} type="button">Cancel</button>
          {{/unless}}
        </div>
      {{/if}}
    {{/if}}
  </template>

  @service declare loaderService: LoaderService;
  @service declare localRealm: LocalRealm;
  @tracked format: Format = this.args.selectedFormat ?? 'edit';
  @tracked card: Card = this.args.card;
  @tracked initialCardData: LooseSingleCardDocument | undefined = undefined;
  private declare interval: ReturnType<typeof setInterval>;
  private lastModified: number | undefined;
  private apiModule = importResource(this, () => `${baseRealm.url}card-api`);

  constructor(owner: unknown, args: Signature['Args']) {
    super(owner, args);
    if (this.args.card.id) {
      this.interval = setInterval(() => taskFor(this.loadData).perform(this.args.card?.id), 1000);
    }
    registerDestructor(this, () => clearInterval(this.interval));
  }

  private get api() {
    if (!this.apiModule.module) {
      throw new Error(
        `bug: card API has not loaded yet--make sure to await this.loaded before using the api`
      );
    }
    return this.apiModule.module as CardAPI;
  }

  private async _currentJSON(includeComputeds: boolean) {
    await this.apiModule.loaded;
    return this.api.serializeCard(this.card, { includeComputeds });
  }

  @cached
  get currentJSON() {
    return this._currentJSON(true);
  }

  @cached
  get comparableCurrentJSON() {
    return this._currentJSON(false);
  }

  // i would expect that this finds a new home after we start refactoring and
  // perhaps end up with a card model more similar to the one the compiler uses
  get isDirty() {
    return true;
    // TODO: dirty checking
    // if (!this.args.card.id) {
    //   return true;
    // }
    // if (!this.json) {
    //   return false;
    // }
    // if (this.initialCardData?.data.id === this.comparableCurrentJSON?.data.id) {
    //   return !isEqual(this.initialCardData, this.comparableCurrentJSON);
    // }
    // return false;
  }

  @action
  setFormat(format: Format) {
    this.format = format;
  }

  @action
  cancel() {
    if (this.args.onCancel) {
      this.args.onCancel();
    }
  }

  @action
  save() {
    taskFor(this.write).perform();
  }

  @restartableTask private async loadData(url: string | undefined): Promise<void> {
    if (!url) {
      return;
    }
    await this.apiModule.loaded;
    let response = await this.loaderService.loader.fetch(url, {
      headers: {
        'Accept': 'application/vnd.api+json'
      },
    });
    let json = await response.json();
    if (!isSingleCardDocument(json)) {
      throw new Error(`bug: server returned a non card document to us for ${url}`);
    }
    if (this.lastModified !== json.data.meta.lastModified) {
      this.lastModified = json.data.meta.lastModified;
      this.initialCardData = await this.getComparableCardJson(json);
    }
  }

  @restartableTask private async write(): Promise<void> {
    await this.apiModule.loaded;
    let url = this.args.card.id ?? this.localRealm.url;
    let method = this.args.card.id ? 'PATCH' : 'POST';
    let currentJSON = await this.currentJSON;
    let response = await this.loaderService.loader.fetch(url, {
      method,
      headers: {
        'Accept': 'application/vnd.api+json'
      },
      body: JSON.stringify(currentJSON, null, 2)
    });

    if (!response.ok) {
      throw new Error(`could not save file, status: ${response.status} - ${response.statusText}. ${await response.text()}`);
    }
    let json = await response.json();
    this.card = await this.api!.createFromSerialized(json.data, this.localRealm.url, { loader: this.loaderService.loader });

    // reset our dirty checking to be detect dirtiness from the
    // current JSON to reflect save that just happened
    this.initialCardData = this.api!.serializeCard(this.card);

    this.args.onSave?.(this.card);
  }

  private async getComparableCardJson(json: LooseSingleCardDocument): Promise<LooseSingleCardDocument | undefined> {
    let card = await this.api!.createFromSerialized(json.data, this.localRealm.url, { loader: this.loaderService.loader });
    return this.api!.serializeCard(card);
  }
}
