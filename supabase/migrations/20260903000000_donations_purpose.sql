-- Lets a donor earmark what their contribution supports (General Programs,
-- Family History Research, Oral History, Record Digitization, Genealogy
-- Education, App Development, or Where Most Needed) — purely informational,
-- doesn't change how the payment is processed. Nullable: older rows and any
-- donation tied to a specific research opportunity leave this unset.

alter table public.donations
  add column if not exists purpose text;

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
        'whereMostNeeded'
      )
    );

comment on column public.donations.purpose is
  'What the donor earmarked this contribution for — matches DonationPurpose enum names in the Flutter app.';
