import logo from './logo.svg';
import './App.css';

function App() {
  return (
    <div className="App">
      <button onClick={test}> test </button>
    </div>
  );
}

function test() {
  console.log("this")
}

export default App;
