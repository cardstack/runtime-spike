import Component from '@glimmer/component';
//@ts-ignore cached not available yet in definitely typed
import { cached } from '@glimmer/tracking';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import isEqual from 'lodash/isEqual';
import { restartableTask, task } from 'ember-concurrency';
import { taskFor } from 'ember-concurrency-ts';
import { registerDestructor } from '@ember/destroyable';
import { service } from '@ember/service';
import RouterService from '@ember/routing/router-service';
import LoaderService from '../services/loader-service';
import { importResource } from '../resources/import';
import { LooseSingleCardDocument,isSingleCardDocument, baseRealm } from '@cardstack/runtime-common';
import type { Format } from 'https://cardstack.com/base/card-api';
import type LocalRealm from '../services/local-realm';
import { RenderedCard } from 'https://cardstack.com/base/render-card';
import FormatPicker from './format-picker';
import type { Card } from 'https://cardstack.com/base/card-api';

type CardAPI = typeof import('https://cardstack.com/base/card-api');
type RenderedCardModule = typeof import('https://cardstack.com/base/render-card');

interface Signature {
  Args: {
    formats?: Format[];
    selectedFormat?: Format;
    card: Card;
    realmURL?: string;
    onCancel?: () => void;
    onSave?: (url: string) => void;
  }
}

export default class Preview extends Component<Signature> {
  <template>
    {{#if @formats}}
      <FormatPicker
        @formats={{@formats}}
        @selectedFormat={{this.format}}
        @setFormat={{this.setFormat}}
      />
    {{/if}}

    {{#if this.renderedCard}}
      <this.renderedCard/>
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
    {{/if}}
  </template>

  @service declare router: RouterService;
  @service declare loaderService: LoaderService;
  @service declare localRealm: LocalRealm;
  @tracked format: Format = !this.args.card.id ? 'edit' : this.args.selectedFormat ?? 'isolated';
  @tracked rendered: RenderedCard | undefined;
  @tracked initialCardData: LooseSingleCardDocument | undefined = undefined;
  private declare interval: ReturnType<typeof setInterval>;
  private lastModified: number | undefined;
  private apiModule = importResource(this, () => `${baseRealm.url}card-api`);
  private renderCardModule = importResource(this, () => `${baseRealm.url}render-card`);

  constructor(owner: unknown, args: Signature['Args']) {
    super(owner, args);
    taskFor(this.prepareNewInstance).perform();
    if (this.args.card.id) {
      this.interval = setInterval(() => taskFor(this.loadData).perform(this.args.card?.id), 1000);
    }
    registerDestructor(this, () => clearInterval(this.interval));
  }

  @cached
  get card() {
    return this.args.card;
  }

  private get api() {
    if (!this.apiModule.module) {
      throw new Error(
        `bug: card API has not loaded yet--make sure to await this.loaded before using the api`
      );
    }
    return this.apiModule.module as CardAPI;
  }

  private get renderCard() {
    if (!this.renderCardModule.module) {
      throw new Error(
        `bug: card API has not loaded yet--make sure to await this.loaded before using the api`
      );
    }
    return this.renderCardModule.module as RenderedCardModule;
  }

  private get apiLoaded() {
    return Promise.all([this.apiModule.loaded, this.renderCardModule.loaded]);
  }

  private _currentJSON(includeComputeds: boolean) {
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
    if (!this.args.card.id) {
      return true;
    }
    if (!this.currentJSON) {
      return false;
    }
    if (this.initialCardData?.data.id === this.comparableCurrentJSON.data.id) {
      return !isEqual(this.initialCardData, this.comparableCurrentJSON);
    }
    return false;
  }

  get renderedCard() {
    return this.rendered?.component
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

  @task private async prepareNewInstance(): Promise<void> {
    await this.apiLoaded;
    if (!this.rendered) {
      this.rendered = this.renderCard.render(this, () => this.card, () => this.format);
    }
  }

  @restartableTask private async loadData(url: string | undefined): Promise<void> {
    if (!url) {
      return;
    }
    await this.apiLoaded;
    if (!this.rendered) {
      this.rendered = this.renderCard.render(this, () => this.card, () => this.format);
    }

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
    let url = this.args.card.id ?? this.args.realmURL;
    let method = this.args.card.id ? 'PATCH' : 'POST';
    let response = await this.loaderService.loader.fetch(url, {
      method,
      headers: {
        'Accept': 'application/vnd.api+json'
      },
      body: JSON.stringify(this.currentJSON, null, 2)
    });

    if (!response.ok) {
      throw new Error(`could not save file, status: ${response.status} - ${response.statusText}. ${await response.text()}`);
    }
    let json = await response.json();

    // reset our dirty checking to be detect dirtiness from the
    // current JSON to reflect save that just happened
    this.initialCardData = await this.getComparableCardJson(this.currentJSON!);

    if (json.data.links?.self) {
      // this is to notify the application route to load a
      // new source path, so we use the actual .json extension
      this.doSave(json.data.links.self + '.json');
    }
  }

  doSave(path: string) {
    if (this.args.onSave) {
      this.args.onSave(path);
    } else {
      this.setFormat('isolated')
    }
  }

  private async getComparableCardJson(json: LooseSingleCardDocument): Promise<LooseSingleCardDocument> {
    let card = await this.api.createFromSerialized(json.data, this.localRealm.url, { loader: this.loaderService.loader });
    return this.api.serializeCard(card);
  }
}
