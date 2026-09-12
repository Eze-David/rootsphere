-- Adds "AI Research Assistants" as a donation purpose option, alongside the
-- existing set from 20260903000000_donations_purpose.sql.

alter table public.donations
  drop constraint if exists donations_purpose_check;

alter table public.donations
  add constraint donations_purpose_check
    check (
      purpose is null or purpose in (
        'generalPrograms',
        'familyHistoryResearch',
        'oralHistory',
        'recordDigitization',
        'genealogyEducation',
        'appDevelopment',
        'aiResearchAssistant',
        'whereMostNeeded'
      )
    );
