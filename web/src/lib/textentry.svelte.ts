/**
 * One text buffer, two ways to fill it.
 *
 * The on-screen keyboard and a physical keyboard are not separate features
 * here. Both arrive as host actions and both write into this buffer, so a
 * DualShock's keyboard attachment and the D-pad can be used interchangeably —
 * mid-word, without a mode switch.
 */

import { firstCharacter, type HostAction } from './host';

export interface Field {
  label: string;
  value: string;
  placeholder?: string;
  /**
   * Search keeps its keyboard on screen permanently, so committing there means
   * "I am done typing, move to the results" rather than "close the field".
   */
  persistent?: boolean;
  /** Fires on every change, for search-as-you-type. */
  onChange?: (value: string) => void;
  onCommit?: (value: string) => void;
  onCancel?: () => void;
}

let field = $state<Field | null>(null);

function change(value: string) {
  if (!field) return;
  field.value = value;
  field.onChange?.(value);
}

export const textEntry = {
  get active(): boolean {
    return field !== null;
  },
  get current(): Field | null {
    return field;
  },

  open(next: Field): void {
    field = { ...next };
  },

  insert(character: string): void {
    if (field) change(field.value + character);
  },

  backspace(): void {
    if (field) change(field.value.slice(0, -1));
  },

  clear(): void {
    if (field) change('');
  },

  commit(): void {
    if (!field) return;
    if (field.persistent) {
      field.onCommit?.(field.value);
      return;
    }
    const done = field;
    field = null;
    done.onCommit?.(done.value);
  },

  cancel(): void {
    const done = field;
    field = null;
    done?.onCancel?.();
  },

  /**
   * Consume typed characters and deletion. Directions and `select` are left
   * alone so they still drive the on-screen keyboard's own focus.
   */
  handle(actions: HostAction[]): boolean {
    if (!field) return false;

    const character = firstCharacter(actions);
    if (character !== null) {
      this.insert(character);
      return true;
    }

    if (actions.includes('back')) {
      // Backspace deletes, which is what the key says on a physical keyboard.
      // With nothing left to delete it means "leave", which is what Escape and
      // a controller's B button mean.
      if (field.value.length > 0) this.backspace();
      else this.cancel();
      return true;
    }

    return false;
  }
};
