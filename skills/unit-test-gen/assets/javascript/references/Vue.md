# Vue Unit Test Quick Reference

Prefer `@vue/test-utils`. Cover props, emits, slots, async updates, and external dependencies.

## Basic Structure

```ts
import { mount } from '@vue/test-utils';

it('emits submit', async () => {
  const wrapper = mount(Form, { props: { disabled: false } });
  await wrapper.find('button').trigger('click');
  expect(wrapper.emitted('submit')).toHaveLength(1);
});
```

## Mount Options

```ts
mount(Component, {
  props: { id: '1' },
  slots: { default: '<span>content</span>' },
  global: {
    plugins: [pinia, router],
    provide: { service },
    mocks: { $t: (k: string) => k },
    stubs: { RouterLink: true },
  },
});
```

## Common Assertions

- Text/DOM: `wrapper.text()`, `wrapper.find(selector).exists()`
- Prop changes: `await wrapper.setProps({ value: 'x' })`
- Forms: `await input.setValue('abc')`
- Events: `wrapper.emitted('update:modelValue')`
- Conditional rendering: cover `v-if`, empty list, loading, and error

## Composition API / Composable

- Pure logic composables can be called directly and asserted.
- If lifecycle, provide/inject, or component instance is needed, mount a test component.
- After reactive updates use `await nextTick()`; after Promises use `flushPromises()`.

## Async Handling

```ts
await wrapper.find('button').trigger('click');
await flushPromises();
await nextTick();
```

Network, router, Pinia actions, and timers should be mocked or provided by test instances.

## Common Mocks

- Router: mock `useRouter` / `useRoute` from `vue-router`.
- Pinia: prefer existing testing pinia; otherwise mock store/actions.
- i18n: `global.mocks.$t = (key) => key`.
- Complex child components: use `global.stubs`.

## Imports

- `mount` / `shallowMount`: `@vue/test-utils`
- `nextTick`: `vue`
- `flushPromises`: existing project helper or ecosystem helper
