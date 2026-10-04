-- Keep backend model_outputs limited to outputs that were actually produced.
-- Unavailable research references remain in the app catalog, not user scan rows.

delete from public.model_outputs
where state = 'unavailable'
   or output_type = 'unavailable';

alter table public.model_outputs
  drop constraint if exists model_outputs_state_check;

alter table public.model_outputs
  add constraint model_outputs_state_check
  check (state in ('bundledExecutable', 'sourceBound'));

alter table public.model_outputs
  drop constraint if exists model_outputs_output_type_check;

alter table public.model_outputs
  add constraint model_outputs_output_type_check
  check (output_type in ('likelihood', 'classification', 'quality', 'summary'));
