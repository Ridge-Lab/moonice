import {run} from './moonice.js';
let source = '';
self.onmessage = ({data}) => {
  const {id, bundle, options} = data;
  if (bundle !== undefined) source = bundle;
  const start = performance.now();
  try { self.postMessage({id, payload: JSON.parse(run(source, JSON.stringify(options))), milliseconds: performance.now()-start}); }
  catch (error) { self.postMessage({id,payload:{ok:false,error:{code:'RUNTIME',path:'worker',message:String(error)}},milliseconds:performance.now()-start}); }
};
