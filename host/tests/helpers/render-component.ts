// @ts-ignore
import { precompileTemplate } from '@ember/template-compilation';
import { render } from '@ember/test-helpers';
import { ComponentLike } from '@glint/template';
import type { Card, Format } from 'https://cardstack.com/base/card-api';

async function cardApi(): Promise<
  typeof import('https://cardstack.com/base/card-api')
> {
  return await import(
    /* webpackIgnore: true */ 'http://localhost:4201/base/card-api' + ''
  );
}

export async function renderComponent(C: ComponentLike) {
  await render(precompileTemplate(`<C/>`, { scope: () => ({ C }) }));
}

export async function renderCard(card: Card, format: Format): Promise<void> {
  let { prepareToRender } = await cardApi();
  let { component } = await prepareToRender(card, format);
  await renderComponent(component);
}
