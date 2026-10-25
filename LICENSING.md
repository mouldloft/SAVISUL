# Licensing

SAVISUL has two parts with two licenses.

| Part | Where | License |
|---|---|---|
| SAVISUL, the app | this repository | [Apache License 2.0](LICENSE), with [NOTICE](NOTICE); the name and logo are covered by [TRADEMARKS.md](TRADEMARKS.md) |
| Mould Engine, the AI engine SAVISUL's assistant runs on | not in this repository | proprietary, © Mould Loft |

## What stays open

Everything in this repository is open source under the Apache License 2.0, and code that has been published under it
stays available under it. Building from source needs nothing closed: without Mould Engine, SAVISUL builds and runs with
every feature it has always had. Only the assistant is left out; its code lives in `Sources/SAVISUL/Mind` and is
compiled only when the engine is present.

## Mould Engine

Mould Engine is Mould Loft's own engine for routing between local and cloud models, building and running action
graphs, keeping a model of the Mac's context, local memory and a secure runtime for actions. It is a separate,
proprietary product. Builds of SAVISUL published by Mould Loft include it in binary form, free of charge, under the
terms that come with those builds. Using Mould Engine in other products needs a license from Mould Loft:
mouldloft@gmail.com.
