/**
 * Does this model quote Hebrew well enough to be trusted with a policy?
 *
 * Asking a model whether it can do something is worthless — it says yes. This
 * gives it the job and marks the result: one page of a (fictional) Hebrew
 * policy, a fixed set of figures to find, and then the *real* verifier from
 * `ingestion/verify.ts` deciding whether each quote actually appears on the
 * page. Nothing here is a second opinion about quality; it is the same gate the
 * product uses, run by hand.
 *
 * A model that chats fluently in Hebrew can still fail this. Reproducing a
 * string character for character out of a right-to-left page is a different
 * skill from speaking the language, and it is the one Covera depends on.
 *
 *   npx tsx scripts/model-trial/run.ts mistral mistral-large-latest
 *   npx tsx scripts/model-trial/run.ts gemini  gemini-2.5-pro
 *
 * Keys come from api/.env (MISTRAL_API_KEY, COVERA_GEMINI_API_KEY) — never from
 * the command line, where they end up in shell history.
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalize, numbersIn } from '../../src/ingestion/verify.js';

const here = dirname(fileURLToPath(import.meta.url));
const PAGE = readFileSync(join(here, 'hebrew-policy-page.txt'), 'utf8');

/** What a correct reading finds. Checked against the model's answer by hand. */
const EXPECTED: Record<string, string> = {
  surgery_coverage_percent: '90',
  per_surgery_cap: '250000',
  annual_cap: '600000',
  waiting_period_days: '90',
  claim_deadline_days: '180',
  deductible: '1500',
};

const ASK = `You are reading one page of a health insurance policy. It is in Hebrew.

For each field below, return the value and a verbatim quote from the page that proves it.

The quote must be copied from the page EXACTLY, character for character. Do not
translate it, do not tidy it, do not reorder words. If the page does not state a
field, use "not_stated" and omit the quote.

Fields: surgery_coverage_percent, per_surgery_cap, annual_cap,
waiting_period_days, claim_deadline_days, deductible

Return only JSON: {"fields": {"<name>": {"value": "<value or not_stated>", "quote": "<verbatim or omitted>"}}}

PAGE:
${PAGE}`;

interface Answer {
  fields?: Record<string, { value?: string; quote?: string }>;
}

async function askMistral(model: string, key: string): Promise<{ text: string; usage: unknown }> {
  const response = await fetch('https://api.mistral.ai/v1/chat/completions', {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model,
      messages: [{ role: 'user', content: ASK }],
      response_format: { type: 'json_object' },
      temperature: 0,
    }),
  });
  if (!response.ok) throw new Error(`Mistral ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const body = (await response.json()) as { choices: { message: { content: string } }[]; usage: unknown };
  return { text: body.choices[0]!.message.content, usage: body.usage };
}

async function askGemini(model: string, key: string): Promise<{ text: string; usage: unknown }> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: ASK }] }],
        generationConfig: { temperature: 0, responseMimeType: 'application/json' },
      }),
    },
  );
  if (!response.ok) throw new Error(`Gemini ${response.status}: ${(await response.text()).slice(0, 300)}`);
  const body = (await response.json()) as {
    candidates: { content: { parts: { text: string }[] } }[];
    usageMetadata: unknown;
  };
  return { text: body.candidates[0]!.content.parts[0]!.text, usage: body.usageMetadata };
}

function main(): Promise<void> {
  const [provider, model] = process.argv.slice(2);
  if (!provider || !model) {
    console.error('usage: run.ts <mistral|gemini> <model>');
    process.exit(1);
  }

  const key = provider === 'mistral' ? process.env.MISTRAL_API_KEY : process.env.COVERA_GEMINI_API_KEY;
  if (!key) {
    console.error(
      `No key. Put ${provider === 'mistral' ? 'MISTRAL_API_KEY' : 'COVERA_GEMINI_API_KEY'} in api/.env and run with --env-file=.env`,
    );
    process.exit(1);
  }

  const ask = provider === 'mistral' ? askMistral : askGemini;
  return ask(model, key).then(({ text, usage }) => score(provider, model, text, usage));
}

function score(provider: string, model: string, text: string, usage: unknown): void {
  let answer: Answer;
  try {
    answer = JSON.parse(text.replace(/^```(?:json)?\n?|\n?```$/g, '')) as Answer;
  } catch {
    console.log(`\n${provider}/${model}: returned something that is not JSON.\n${text.slice(0, 400)}`);
    return;
  }

  // The page as the verifier sees it: bidi and zero-width marks removed, so a
  // model is not failed for invisible characters nobody can see.
  const page = normalize(PAGE);
  let right = 0;
  let quoted = 0;

  console.log(`\n${provider} / ${model}\n${'-'.repeat(46)}`);
  for (const [field, expected] of Object.entries(EXPECTED)) {
    const got = answer.fields?.[field];
    const value = (got?.value ?? '').trim();
    const quote = (got?.quote ?? '').trim();

    // Compare the digits, not the formatting: 250,000 and 250000 are the value.
    const valueOk = numbersIn(value).join() === numbersIn(expected).join();
    // The quote has to be findable on the page. This is the whole test.
    const quoteOk = quote.length > 0 && page.includes(normalize(quote));

    if (valueOk) right += 1;
    if (valueOk && quoteOk) quoted += 1;

    const mark = !valueOk ? 'WRONG VALUE' : quoteOk ? 'ok' : 'QUOTE NOT ON PAGE';
    console.log(`  ${field.padEnd(26)} ${String(value || '—').padEnd(10)} ${mark}`);
  }

  console.log(`${'-'.repeat(46)}`);
  console.log(`  values right:            ${right}/${Object.keys(EXPECTED).length}`);
  console.log(`  quotes the verifier accepts: ${quoted}/${Object.keys(EXPECTED).length}`);
  console.log(`  usage: ${JSON.stringify(usage)}`);
  console.log(
    `\n  A model is only usable here if the second number matches the first.\n` +
      `  A right figure with an unfindable quote is exactly what Covera refuses to show.\n`,
  );
}

await main();
