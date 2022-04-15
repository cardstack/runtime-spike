import { languages } from 'monaco-editor/esm/vs/editor/editor.api';

import {
  conf as jsConfig,
  language as js,
} from 'monaco-editor/esm/vs/basic-languages/javascript/javascript';

export const gjsRegistryInfo: languages.ILanguageExtensionPoint = {
  id: 'glimmerJS',
  extensions: ['.gjs'],
};

export const gjsConfig: languages.LanguageConfiguration = {
  ...jsConfig,
  autoClosingPairs: [
    { open: '<!--', close: '-->', notIn: ['comment', 'string'] },
    { open: '<template>', close: '</template>' },
    ...jsConfig.autoClosingPairs,
  ],
};

export const gjsDefinition: languages.IMonarchLanguage = {
  ...js,
  tokenPostfix: '.gjs',
  tokenizer: {
    ...js.tokenizer,
    root: [
      [
        /<template\s*>/,
        {
          token: 'tag',
          bracket: '@open',
          next: '@hbs',
          nextEmbedded: 'handlebars',
        },
      ],
      [/<\/template\s*>/, { token: 'tag', bracket: '@close' }],
      ...js.tokenizer.root,
    ],
    hbs: [
      [
        /<\/template\s*>/,
        { token: '@rematch', next: '@pop', nextEmbedded: '@pop' },
      ],
    ],
  },
};
